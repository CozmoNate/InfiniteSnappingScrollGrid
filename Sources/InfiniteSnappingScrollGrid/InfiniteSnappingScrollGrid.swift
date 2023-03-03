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


import SwiftUI
import Algorithms

public struct InfiniteSnappingScrollGrid<Item: Hashable, Identifier: Hashable, Content: View>: View {
    
    @Binding
    private var referenceItems: [Item]
    private let identifierKeyPath: KeyPath<Item, Identifier>
    private let alignment: Axis
    private let itemContent: (Item, Int) -> Content
    private let itemBefore: (Item) -> Item
    private let itemAfter: (Item) -> Item
    
    @State
    private var actualItems: [Item] = []
    
    @State
    private var itemPositions: [Int] = []
    
    @State
    private var dragStart: CGFloat = 0
    
    @State
    private var dragOffset: CGFloat = 0
    
    @State
    private var isLocked = false
    
    @State
    private var dismantleIndex: Int?
    
    @MainActor public var body: some View {
        GeometryReader { geometry in
            
            let itemSize = alignedAxis(from:  geometry.size) / CGFloat(referenceItems.count)
            
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
                            width: alignedAxis(from: itemSize, direction: .horizontal) ??
                            reversedAxis(from: geometry.size.width, direction: .horizontal),
                            height: alignedAxis(from: itemSize, direction: .vertical) ??
                            reversedAxis(from: geometry.size.height, direction: .vertical)
                        )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        handleScrollChanged(with: value.translation, itemSize: itemSize)
                    }
                    .onEnded { value in
                        handleScrollEnded(with: value.translation, itemSize: itemSize)
                    },
                including: isLocked ? .gesture : .all)
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
    
    internal init(
        referenceRows: Binding<[Item]>,
        identifierKeyPath: KeyPath<Item, Identifier>,
        alignment: Axis,
        itemContent: @escaping (Item, Int) -> Content,
        itemBefore: @escaping (Item) -> Item,
        itemAfter: @escaping (Item) -> Item
    ) {
        _referenceItems = referenceRows
        self.identifierKeyPath = identifierKeyPath
        self.alignment = alignment
        self.itemContent = itemContent
        self.itemBefore = itemBefore
        self.itemAfter = itemAfter
    }
    
    private func refreshRowsAndPositions(with rows: [Item]) {
        actualItems = assembleItems(fromReferenceItems: rows)
        itemPositions = Array(actualItems.indices)
        referenceItems = visibleItems(fromAllItems: actualItems, at: itemPositions)
    }
    
    private func alignedAxis(from size: CGSize) -> CGFloat {
        switch alignment {
        case .horizontal: return size.width
        case .vertical: return size.height
        }
    }
    
    private func reversedAxis(from size: CGSize) -> CGFloat {
        switch alignment {
        case .horizontal: return size.height
        case .vertical: return size.width
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
    
    private func reversedAxis(from size: CGFloat, direction: Axis) -> CGFloat? {
        switch (alignment, direction) {
        case (.horizontal, .horizontal), (.vertical, .vertical): return nil
        case (.horizontal, .vertical), (.vertical, .horizontal): return size
        }
    }
    
    private func handleScrollChanged(with translation: CGSize, itemSize: CGFloat) {
        let axisOffset = alignedAxis(from: translation)
        
        guard isLocked || abs(axisOffset) > abs(reversedAxis(from: translation)) else {
            return
        }
        
        isLocked = true
        dragOffset = axisOffset
        
        let relativeOffset = axisOffset - dragStart
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
            let threshold = itemSize / 2
            if dragOffset > threshold {
                dismantleLaterItem()
            } else if dragOffset < -threshold {
                dismantleEarlierItem()
            }
            dragOffset = 0
            dragStart = 0
            isLocked = false
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
        referenceItems = visibleItems(fromAllItems: updatedRows, at: updatedPositions)
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
        referenceItems = visibleItems(fromAllItems: updatedRows, at: updatedPositions)
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

private extension Axis {
    
    var edgeSet: Edge.Set {
        switch self {
        case .horizontal: return .horizontal
        case .vertical: return .vertical
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
    init(
        _ items: Binding<[Item]>,
        id: KeyPath<Item, Identifier>,
        alignment: Axis = .vertical,
        @ViewBuilder itemContent: @escaping (Item, Int) -> Content,
        itemBefore: @escaping (Item) -> Item,
        itemAfter: @escaping (Item) -> Item
    ) {
        self = Self.init(
            referenceRows: items,
            identifierKeyPath: id,
            alignment: alignment,
            itemContent: itemContent,
            itemBefore: itemBefore,
            itemAfter: itemAfter
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
    init(
        _ items: Binding<[Item]>,
        alignment: Axis = .vertical,
        @ViewBuilder itemContent: @escaping (Item, Int) -> Content,
        itemBefore: @escaping (Item) -> Item,
        itemAfter: @escaping (Item) -> Item
    ) {
        self = Self.init(
            referenceRows: items,
            identifierKeyPath: \.self,
            alignment: alignment,
            itemContent: itemContent,
            itemBefore: itemBefore,
            itemAfter: itemAfter
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
    init(
        _ items: Binding<[Item]>,
        alignment: Axis = .vertical,
        @ViewBuilder itemContent: @escaping (Item, Int) -> Content,
        itemBefore: @escaping (Item) -> Item,
        itemAfter: @escaping (Item) -> Item
    ) {
        self = Self.init(
            referenceRows: items,
            identifierKeyPath: \.id,
            alignment: alignment,
            itemContent: itemContent,
            itemBefore: itemBefore,
            itemAfter: itemAfter
        )
    }
}

struct InfiniteSnappingScrollGrid_Previews: PreviewProvider {
    
    static var previews: some View {
        Preview()
    }
    
    struct Preview: View {
        
        struct Item: View {
            
            var value: Int
            
            @State
            var isSelected = false
            
            @State
            var offset = CGSize.zero
            
            var body: some View {
                Text(String(value))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(offset)
                    .padding()
                    .background(isSelected ? Color(.secondarySystemBackground) : Color(.systemBackground))
                    .border(.red)
                    .onTapGesture {
                        isSelected.toggle()
                    }
                    .gesture(DragGesture().onChanged { payload in
                        offset = payload.translation
                    }.onEnded{ _ in
                        offset = .zero
                    })
            }
        }
        
        @State
        var items = [1, 2, 3]
        
        var dragGesture = DragGesture()
        
        var body: some View {
            VStack {
                
                Text("Visible items: [\(String(items.map({ String($0) }).joined(by: ", ")))]")
                    .lineLimit(1)
                    .padding()
                    .zIndex(1)
                
                InfiniteSnappingScrollGrid(
                    referenceRows: $items,
                    identifierKeyPath: \.self,
                    alignment: .vertical
                ) { item, index in
                    Item(value: item)
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

