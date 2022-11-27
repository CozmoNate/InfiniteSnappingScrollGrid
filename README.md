# InfiniteSnappingScrollGrid

[![License](https://img.shields.io/badge/license-MIT-ff69b4.svg)](https://github.com/kzlekk/InfiniteSnappingScrollGrid/raw/master/LICENSE)
![Language](https://img.shields.io/badge/swift-5.7-orange.svg)
![Framework](https://img.shields.io/badge/swiftui-2.0-yellowgreen.svg)

A grid that allows a two-way scroll of an infinite number of items using SwiftUI 2+.  

## Installation

### Swift Package Manager

Add "InfiniteSnappingScrollGrid" dependency via integrated Swift Package Manager in XCode

## Usage

InfiniteSnappingScrollGrid requires binding to the array of initial items. Initial items count defines the number of rows or columns displayed simultaneously inside grid bounds. Item contents will be sized equally alongside scroll axis and will be stretched to grid bounds on opposite axis. Bindings to initial items will be updated  with the array of actual visible items every time the content of the grid is scrolled and snapped to new item. 

Example code:

```swift

        @State
        var items = ["one", "two", "three"]
        
        var body: some View {
            InfiniteSnappingScrollGrid($items, alignment: .vertical) { item, index in
                // The content of single row/column
                Text(item)
            } itemBefore: { item in
                // Returns new item that is positioned before designated item
                "\(item).before"
            } itemAfter: { item in
                // Returns new item that is positioned after designated item
                "\(item).after"
            }
            // Perform scroll immediately. Small values improves scroll responsiveness but can break drag-and-drop gestures.  
            .scrollGestureMinimumDistance(0)
        }
    
```
