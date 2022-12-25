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

@MainActor
public struct UIKitBackedScrollGrid<Item: Hashable, Identifier: Hashable, Content: View>: View {
    
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
    private var scrollOffset: CGSize = .zero
    
    @State
    private var scrollMinimumDistance: CGFloat = 10
    
    public var body: some View {
        GeometryReader { geometry in
            
            let itemSize = alignedAxis(from: geometry.size) / CGFloat(referenceItems.count)
            
            WrappedScrollView(contentOffset: $scrollOffset) {

                alignedContainer {
                    ForEach(Array(itemPositions.enumerated()), id: \.element) { index, position in
                        itemContent(actualItems[position], index - 1)
                            .frame(
                                width: alignedAxis(from: itemSize, direction: .horizontal) ??
                                    reversedAxis(from: geometry.size.width, direction: .horizontal),
                                height: alignedAxis(from: itemSize, direction: .vertical) ??
                                    reversedAxis(from: geometry.size.height, direction: .vertical)
                            )
                    }
                }
                .frame(
                    width: reversedAxis(from: geometry.size.width, direction: .horizontal) ??
                        alignedAxis(from: itemSize * CGFloat(referenceItems.count + 2), direction: .horizontal),
                    height: reversedAxis(from: geometry.size.height, direction: .vertical) ??
                        alignedAxis(from: itemSize * CGFloat(referenceItems.count + 2), direction: .vertical)
                )
                .onAppear {
                    scrollOffset = alignedSize(from: itemSize - 1)
                    refreshRowsAndPositions(with: referenceItems)
                }
                .onChange(of: itemSize) { newValue in
                    scrollOffset = alignedSize(from: itemSize - 1)
                }
                .onChange(of: scrollOffset) { offset in
                    handleScrollChanged(with: offset, itemSize: itemSize)
                }
                .onChange(of: referenceItems) { newItems in
                    if actualItems.isEmpty || newItems != visibleItems(fromAllItems: actualItems, at: itemPositions) {
                        refreshRowsAndPositions(with: newItems)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    
    @ViewBuilder private func alignedContainer(@ViewBuilder content: () -> some View) -> some View {
        switch alignment {
        case .horizontal:
            HStack(spacing: 0) {
                content()
            }
        case .vertical:
            VStack(spacing: 0) {
                content()
            }
        }
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
    
    private func alignedSize(from size: CGFloat) -> CGSize {
        switch alignment {
        case .horizontal: return CGSize(width: size, height: 0)
        case .vertical: return CGSize(width: 0, height: size)
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
    
    private func reversedAxis(from size: CGFloat, direction: Axis) -> CGFloat {
        switch (alignment, direction) {
        case (.horizontal, .horizontal), (.vertical, .vertical): return 0
        case (.horizontal, .vertical), (.vertical, .horizontal): return size
        }
    }
    
    private func handleScrollChanged(with translation: CGSize, itemSize: CGFloat) {
        let offset = alignedAxis(from: translation)
        if offset < 0 {
            scrollOffset = alignedSize(from: itemSize)
            dismantleLaterItem()
        }
        else if offset >= itemSize * 2 {
            scrollOffset = alignedSize(from: itemSize)
            dismantleEarlierItem()
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

public extension UIKitBackedScrollGrid {
    
    /// Changes scroll gesture minimum distance
    /// - Parameter distance: The minimum dragging distance for the scroll gesture to start scrolling the content.
    func scrollGestureMinimumDistance(_ distance: CGFloat) -> Self {
        scrollMinimumDistance = distance
        return self
    }
}

struct WrappedScrollView<Content: View>: UIViewControllerRepresentable {
    
    var content: () -> Content
    
    @Binding
    var contentOffset: CGSize
    
    init(contentOffset: Binding<CGSize>, @ViewBuilder content: @escaping () -> Content) {
        self.content = content
        _contentOffset = contentOffset
    }

    func makeCoordinator() -> Controller {
        return Controller(parent: self)
    }

    func makeUIViewController(context: Context) -> ScrollViewController {
        let vc = ScrollViewController()
        vc.scrollView.contentInsetAdjustmentBehavior = .never
        vc.hostingController.rootView = AnyView(content())
        vc.view.layoutIfNeeded()
        vc.scrollView.contentOffset = CGPoint(x: contentOffset.width, y: contentOffset.height)
        vc.scrollView.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ viewController: ScrollViewController, context: Context) {
        viewController.hostingController.rootView = AnyView(content())
        
        let contentOffset = CGPoint(x: contentOffset.width, y: contentOffset.height)
        
        if _contentOffset.transaction.animation == nil {
            viewController.scrollView.contentOffset = contentOffset
        } else {
            viewController.scrollView.setContentOffset(contentOffset, animated: true)
        }
    }

    class Controller: NSObject, UIScrollViewDelegate {
        var parent: WrappedScrollView<Content>
        init(parent: WrappedScrollView<Content>) {
            self.parent = parent
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            parent.$contentOffset.wrappedValue = CGSize(
                width: scrollView.contentOffset.x,
                height: scrollView.contentOffset.y
            )
        }
    }
    
    class ScrollViewController: UIViewController {
        
        lazy var scrollView: UIScrollView = {
            let scrollView = UIScrollView()
            scrollView.isPagingEnabled = true
            scrollView.isDirectionalLockEnabled = true
            scrollView.showsVerticalScrollIndicator = false
            scrollView.showsHorizontalScrollIndicator = false
            return scrollView
        }()

        var hostingController: UIHostingController<AnyView> = UIHostingController(rootView: AnyView(EmptyView()))

        override func viewDidLoad() {
            super.viewDidLoad()
            view.addSubview(scrollView)
            pinEdges(of: scrollView, to: view)

            hostingController.willMove(toParent: self)
            scrollView.addSubview(hostingController.view)
            pinEdges(of: hostingController.view, to: scrollView)
            
            hostingController.didMove(toParent: self)
        }

        func pinEdges(of viewA: UIView, to viewB: UIView) {
            viewA.translatesAutoresizingMaskIntoConstraints = false
            
            viewB.addConstraints([
                viewA.leadingAnchor.constraint(equalTo: viewB.leadingAnchor),
                viewA.trailingAnchor.constraint(equalTo: viewB.trailingAnchor),
                viewA.topAnchor.constraint(equalTo: viewB.topAnchor),
                viewA.bottomAnchor.constraint(equalTo: viewB.bottomAnchor),
            ])
        }
    }
}

struct UIKitBackedScrollGrid_Previews: PreviewProvider {
    
    static var previews: some View {
        Preview()
    }
    
    struct Preview: View {
        
        @State
        var items = [1, 2, 3, 4, 5]
        
        var body: some View {
            VStack {
                
                Text("Visible items: [\(String(items.map({ String($0) }).joined(by: ", ")))]")
                    .lineLimit(1)
                    .padding()
                    .zIndex(1)
                
                UIKitBackedScrollGrid(
                    referenceRows: $items,
                    identifierKeyPath: \.self,
                    alignment: .vertical
                ) { item, index in
                    Text(String(item))
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
