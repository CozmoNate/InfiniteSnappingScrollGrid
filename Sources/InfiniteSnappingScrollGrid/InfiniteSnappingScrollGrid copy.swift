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
public struct InfiniteSnappingScrollGrid<Item: Hashable, Identifier: Hashable, Content: View>: View {
    
    @Binding
    private var referenceItems: [Item]
    private let identifierKeyPath: KeyPath<Item, Identifier>
    private let alignment: Axis
    private let itemContent: (Item, Int) -> Content
    private let itemBefore: (Item) -> Item
    private let itemAfter: (Item) -> Item
    
    public var body: some View {
        #if targetEnvironment(macCatalyst)
            UIKitBackedScrollGrid(
                referenceRows: $referenceItems,
                identifierKeyPath: identifierKeyPath,
                alignment: alignment,
                itemContent: itemContent,
                itemBefore: itemBefore,
                itemAfter: itemAfter
            )
        #else
            SwiftUIBackedScrollGrid(
                referenceRows: $referenceItems,
                identifierKeyPath: identifierKeyPath,
                alignment: alignment,
                itemContent: itemContent,
                itemBefore: itemBefore,
                itemAfter: itemAfter
            )
        #endif
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

struct InfiniteSnappingScrollGrid_Previews: PreviewProvider {
    
    static var previews: some View {
        Preview()
    }
    
    struct Preview: View {
        
        @State
        var items = [1, 2, 3]
        
        var body: some View {
            VStack {
                
                Text("Visible items: [\(String(items.map({ String($0) }).joined(by: ", ")))]")
                    .lineLimit(1)
                    .padding()
                    .zIndex(1)
                
                InfiniteSnappingScrollGrid($items, alignment: .vertical) { item, index in
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
