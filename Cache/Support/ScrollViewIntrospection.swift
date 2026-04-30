//
//  ScrollViewIntrospection.swift
//  Cache
//

import SwiftUI
import UIKit

final class WeakScrollViewStore: ObservableObject {
    weak var scrollView: UIScrollView?
}

struct ScrollViewAccessor: UIViewRepresentable {
    let store: WeakScrollViewStore

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        updateScrollView(from: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        updateScrollView(from: uiView)
    }

    private func updateScrollView(from view: UIView) {
        DispatchQueue.main.async {
            let resolvedScrollView = view.enclosingScrollView
            if store.scrollView !== resolvedScrollView {
                store.scrollView = resolvedScrollView
            }
        }
    }
}

extension UIView {
    var enclosingScrollView: UIScrollView? {
        var view = superview
        while let current = view {
            if let scrollView = current as? UIScrollView {
                return scrollView
            }
            view = current.superview
        }
        return nil
    }
}

extension UIScrollView {
    func stopDeceleratingImmediately() {
        setContentOffset(contentOffset, animated: false)
        layer.removeAllAnimations()
    }
}
