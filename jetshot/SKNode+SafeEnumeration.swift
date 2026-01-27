//
//  SKNode+SafeEnumeration.swift
//  jetshot
//
//  Created by Robert Libšanský on 27.01.2026.
//

import SpriteKit

/// Extension providing safer node enumeration with automatic weak self handling
extension SKNode {

    /// Safely enumerates child nodes with automatic weak self capture
    /// Prevents retain cycles and provides early exit on deallocation
    func safeEnumerateChildNodes<T: AnyObject>(
        withName name: String,
        caller: T,
        using block: @escaping (SKNode, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        enumerateChildNodes(withName: name) { [weak caller] node, stop in
            guard caller != nil else {
                stop.pointee = true
                return
            }
            block(node, stop)
        }
    }
}
