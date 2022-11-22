/*
 * Copyright (c) 2022 Natan Zalkin
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 */


import UIKit
import SwiftUI
import Algorithms

@MainActor
public struct InfiniteSnappingScrollGrid<Item: Hashable, Identifier: Hashable, Content: View>: View {
    
    @Binding
    private var referenceItems: [Item]
    private let identifierKeyPath: KeyPath<Item, Identifier>
    private let alignment: Axis
    private let itemContent: (Item, Int) -> Content
    private let itemBefore: (Item) -> Item
    private let itemAfter: (Item) -> Item
    private let onItemsChanged: (([Item]) -> Void)?
    
    @State
    private var actualItems: [Item] = []
    
    @State
    private var itemPositions: [Int] = []
    
    @State
    private var dragStart: CGFloat = 0
    
    @State
    private var dragOffset: CGFloat = 0
    
    @State
    private var dismantleIndex: Int?
    
    public var body: some View {
        GeometryReader { geometry in
            
            let itemSize = alignedAxis(from:  geometry.size) / CGFloat(referenceItems.count)

            #if targetEnvironment(macCatalyst)
            PanningContainer {
                content(itemSize: itemSize)
            } onChanged: { translation in
                handleScrollChanged(with: translation, itemSize: itemSize)
            } onEnded: { translation in
                handleScrollEnded(with: translation, itemSize: itemSize)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            #else
            content(itemSize: itemSize)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 16, coordinateSpace: .local)
                        .onChanged { value in
                            handleScrollChanged(with: value.translation, itemSize: itemSize)
                        }
                        .onEnded { value in
                            handleScrollEnded(with: value.translation, itemSize: itemSize)
                        }
                )
            #endif
        }
        .onAppear {
            refreshRowsAndPositions(with: referenceItems)
        }
        .onChange(of: dismantleIndex) { target in
            dismantleIndex = .none
        }
        .onChange(of: referenceItems) { newItems in
            if actualItems.isEmpty || newItems != visibleItems(fromAllItems: actualItems, at: itemPositions) {
                refreshRowsAndPositions(with: newItems)
            }
        }
    }
    
    fileprivate init(
        referenceRows: Binding<[Item]>,
        identifierKeyPath: KeyPath<Item, Identifier>,
        alignment: Axis,
        itemContent: @escaping (Item, Int) -> Content,
        itemBefore: @escaping (Item) -> Item,
        itemAfter: @escaping (Item) -> Item,
        onItemsChanged: (([Item]) -> Void)?
    ) {
        _referenceItems = referenceRows
        self.identifierKeyPath = identifierKeyPath
        self.alignment = alignment
        self.itemContent = itemContent
        self.itemBefore = itemBefore
        self.itemAfter = itemAfter
        self.onItemsChanged = onItemsChanged
    }
    
    private func refreshRowsAndPositions(with rows: [Item]) {
        actualItems = assembleItems(fromReferenceItems: rows)
        itemPositions = Array(actualItems.indices)
        let visibleRows = visibleItems(fromAllItems: actualItems, at: itemPositions)
        onItemsChanged?(visibleRows)
        referenceItems = visibleRows
    }
    
    private func alignedAxis(from size: CGSize) -> CGFloat {
        switch alignment {
        case .horizontal: return size.width
        case .vertical: return size.height
        }
    }
    
    private func alignedAxis(from size: CGFloat, direction: Axis) -> CGFloat {
        switch (alignment, direction) {
        case (.horizontal, .horizontal), (.vertical, .vertical): return size
        case (.horizontal, .vertical), (.vertical, .horizontal): return 0
        }
    }
    
    private func alignedAxis(from size: CGFloat, direction: Axis) -> CGFloat? {
        switch (alignment, direction) {
        case (.horizontal, .horizontal), (.vertical, .vertical): return size
        case (.horizontal, .vertical), (.vertical, .horizontal): return nil
        }
    }
    
    private func reversedAxis(from size: CGSize) -> CGFloat {
        switch alignment {
        case .horizontal: return size.height
        case .vertical: return size.width
        }
    }
    
    private func reversedAxis(from size: CGFloat, direction: Axis) -> CGFloat? {
        switch (alignment, direction) {
        case (.horizontal, .horizontal), (.vertical, .vertical): return nil
        case (.horizontal, .vertical), (.vertical, .horizontal): return size
        }
    }
    
    @ViewBuilder
    private func content(itemSize: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(itemPositions.enumerated()), id: \.element) { index, position in
                
                let rowOffset = CGFloat(index - 1) * itemSize + dragOffset - dragStart
                    
                itemContent(actualItems[position], index - 1)
                    .transaction { transaction in
                        if dismantleIndex == index {
                            transaction.animation = nil
                            transaction.disablesAnimations = true
                        }
                    }
                    .offset(
                        x: alignedAxis(from: rowOffset, direction: .horizontal),
                        y: alignedAxis(from: rowOffset, direction: .vertical)
                    )
                    .frame(
                        width: alignedAxis(from: itemSize, direction: .horizontal),
                        height: alignedAxis(from: itemSize, direction: .vertical)
                    )
                    .frame(
                        maxWidth: reversedAxis(from: .infinity, direction: .horizontal),
                        maxHeight: reversedAxis(from: .infinity, direction: .vertical)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private func handleScrollChanged(with translation: CGSize, itemSize: CGFloat) {
        dragOffset = alignedAxis(from: translation)
        let relativeOffset = dragOffset - dragStart
        if relativeOffset >= itemSize {
            dragStart += itemSize
            dismantleLaterItem()
        } else if relativeOffset <= -itemSize {
            dragStart -= itemSize
            dismantleEarlierItem()
        }
    }
    
    private func handleScrollEnded(with translation: CGSize, itemSize: CGFloat) {
        withAnimation(.easeOut(duration: 0.2)) {
            #if targetEnvironment(macCatalyst)
            let threshold = CGFloat(8)
            #else
            let threshold = itemSize / 2
            #endif
            if dragOffset > threshold {
                dismantleLaterItem()
            } else if dragOffset < -threshold {
                dismantleEarlierItem()
            }
            dragOffset = 0
            dragStart = 0
        }
    }
    
    private func dismantleEarlierItem() {
        let dismantlePosition = itemPositions[itemPositions.startIndex]
        let targetPosition = itemPositions[itemPositions.endIndex - 1]
        var updatedRows = actualItems
        var updatedPositions = itemPositions
        updatedRows[dismantlePosition] = itemAfter(updatedRows[targetPosition])
        updatedPositions.rotate(toStartAt: updatedPositions.startIndex + 1)
        actualItems = updatedRows
        itemPositions = updatedPositions
        dismantleIndex = updatedPositions.endIndex - 1
        
        let visibleRows = visibleItems(fromAllItems: updatedRows, at: updatedPositions)
        onItemsChanged?(visibleRows)
        referenceItems = visibleRows
    }
    
    private func dismantleLaterItem() {
        let dismantlePosition = itemPositions[itemPositions.endIndex - 1]
        let targetPosition = itemPositions[itemPositions.startIndex]
        var updatedRows = actualItems
        var updatedPositions = itemPositions
        updatedRows[dismantlePosition] = itemBefore(updatedRows[targetPosition])
        updatedPositions.rotate(toStartAt: updatedPositions.endIndex - 1)
        actualItems = updatedRows
        itemPositions = updatedPositions
        dismantleIndex = updatedPositions.startIndex
        
        let visibleRows = visibleItems(fromAllItems: updatedRows, at: updatedPositions)
        onItemsChanged?(visibleRows)
        referenceItems = visibleRows
    }
    
    private func assembleItems(fromReferenceItems referenceItems: [Item]) -> [Item] {
        [itemBefore(referenceItems[referenceItems.startIndex])] + referenceItems
            + [itemAfter(referenceItems[referenceItems.index(before: referenceItems.endIndex)])]
    }
    
    private func visibleItems(fromAllItems allItems: [Item], at itemPositions: [Int]) -> [Item] {
        itemPositions[(itemPositions.startIndex + 1)...(itemPositions.endIndex - 2)].map {
            allItems[$0]
        }
    }
}

public extension InfiniteSnappingScrollGrid {
    
    /// Creates a grid that identifies its items based on a key path to the identifier of the underlying item data
    /// - Parameters:
    ///   - items: The initial items & a binding to the array of displayed items.
    ///   - id: The key path to the item identifier.
    ///   - alignment: The items alignment axis. Also defines allowed scroll axis.
    ///   - itemContent: A view builder that creates the view for a single item. The index of the item is relative to items displayed and goes beyond the bounds of displayed items array.
    ///   - itemBefore: An item provider that returns previous item positioned before designed item.
    ///   - itemAfter: An item provider that returns next item positioned after designed item.
    ///   - onItemsChanged: A callback called every time items changed
    init(
        _ items: Binding<[Item]>,
        id: KeyPath<Item, Identifier>,
        alignment: Axis = .vertical,
        @ViewBuilder itemContent: @escaping (Item, Int) -> Content,
        itemBefore: @escaping (Item) -> Item,
        itemAfter: @escaping (Item) -> Item,
        onItemsChanged: (([Item]) -> Void)? = nil
    ) {
        self = Self.init(
            referenceRows: items,
            identifierKeyPath: id,
            alignment: alignment,
            itemContent: itemContent,
            itemBefore: itemBefore,
            itemAfter: itemAfter,
            onItemsChanged: onItemsChanged
        )
    }
}

public extension InfiniteSnappingScrollGrid where Item == Identifier {

    /// Creates a grid based on a collection of identifiable items
    /// - Parameters:
    ///   - items: The initial items & a binding to the array of displayed items.
    ///   - alignment: The items alignment axis. Also defines allowed scroll axis.
    ///   - itemContent: A view builder that creates the view for a single item. The index of the item is relative to items displayed and goes beyond the bounds of displayed items array.
    ///   - itemBefore: An item provider that returns previous item positioned before designed item.
    ///   - itemAfter: An item provider that returns next item positioned after designed item.
    ///   - onItemsChanged: A callback called every time items changed
    init(
        _ items: Binding<[Item]>,
        alignment: Axis = .vertical,
        @ViewBuilder itemContent: @escaping (Item, Int) -> Content,
        itemBefore: @escaping (Item) -> Item,
        itemAfter: @escaping (Item) -> Item,
        onItemsChanged: (([Item]) -> Void)? = nil
    ) {
        self = Self.init(
            referenceRows: items,
            identifierKeyPath: \.self,
            alignment: alignment,
            itemContent: itemContent,
            itemBefore: itemBefore,
            itemAfter: itemAfter,
            onItemsChanged: onItemsChanged
        )
    }
}

public extension InfiniteSnappingScrollGrid where Item: Identifiable, Item.ID == Identifier {

    /// Creates a grid based on a collection of identifiable items
    /// - Parameters:
    ///   - items: The initial items & a binding to the array of displayed items.
    ///   - alignment: The items alignment axis. Also defines allowed scroll axis.
    ///   - itemContent: A view builder that creates the view for a single item. The index of the item is relative to items displayed and goes beyond the bounds of displayed items array.
    ///   - itemBefore: An item provider that returns previous item positioned before designed item.
    ///   - itemAfter: An item provider that returns next item positioned after designed item.
    ///   - onItemsChanged: A callback called every time items changed
    init(
        _ items: Binding<[Item]>,
        alignment: Axis = .vertical,
        @ViewBuilder itemContent: @escaping (Item, Int) -> Content,
        itemBefore: @escaping (Item) -> Item,
        itemAfter: @escaping (Item) -> Item,
        onItemsChanged: (([Item]) -> Void)? = nil
    ) {
        self = Self.init(
            referenceRows: items,
            identifierKeyPath: \.id,
            alignment: alignment,
            itemContent: itemContent,
            itemBefore: itemBefore,
            itemAfter: itemAfter,
            onItemsChanged: onItemsChanged
        )
    }
}

fileprivate struct PanningContainer<Content: View>: UIViewControllerRepresentable {
    
    let content: Content
    let onChanged: (CGSize) -> Void
    let onEnded: (CGSize) -> Void
    
    init(@ViewBuilder _ content: () -> Content,
         onChanged: @escaping (CGSize) -> Void,
         onEnded: @escaping(CGSize) -> Void) {
        self.content = content()
        self.onChanged = onChanged
        self.onEnded = onEnded
    }
    
    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let contentController = UIHostingController(rootView: content)
        
        contentController.loadView()
        
        let panGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(sender:))
        )
        panGesture.allowedScrollTypesMask = [.continuous, .discrete]
        
        contentController.view.addGestureRecognizer(panGesture)
        
        return contentController
    }
    
    func updateUIViewController(_ uiViewController: UIHostingController<Content>, context: Context) {
        uiViewController.view.gestureRecognizers?.forEach {
            $0.delegate = context.coordinator
        }
        uiViewController.rootView = content
        context.coordinator.target = uiViewController.viewIfLoaded
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }
    
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.onChanged = onChanged
        coordinator.onEnded = onEnded
        return coordinator
    }
    
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        
        var target: UIView?
        
        var onChanged: ((CGSize) -> Void)?
        var onEnded: ((CGSize) -> Void)?
        
        @objc func handlePan(sender: UIPanGestureRecognizer) {
            if let target {
                let point = sender.translation(in: target)
                let translation = CGSize(width: point.x, height: point.y)
                if max(abs(translation.width), abs(translation.height)) > 8 {
                    switch sender.state {
                    case .began, .changed:
                        onChanged?(translation)
                    case .ended:
                        onEnded?(translation)
                    default:
                        break
                    }
                }
            }
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
    }
}

struct InfiniteSnappingScrollGrid_Previews: PreviewProvider {
    
    static var previews: some View {
        Preview()
    }
    

    
    struct Preview: View {
        
        static var ordinalListItemFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.formattingContext = .listItem
            formatter.numberStyle = .ordinal
            return formatter
        }
        
        @State
        var items = [1, 2, 3]
        
        var body: some View {
            VStack {
                
                Text("Visible items: [\(String(items.map({ String($0) }).joined(by: ", ")))]")
                    .lineLimit(1)
                    .padding()
                    .zIndex(1)
                
                InfiniteSnappingScrollGrid($items, alignment: .vertical) { item, index in
                    let title = item == 0 ? "Zero" : "\(Preview.ordinalListItemFormatter.string(from: NSNumber(integerLiteral: item)) ?? String(item))"
                    Text(title)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                        .background(Color(.systemBackground))
                        .border(.red)
                } itemBefore: { item in
                    item - 1
                } itemAfter: { item in
                    item + 1
                }
                .border(.blue)
                .padding(.bottom, 16)
            }
            .border(.green)
        }
    }
}
