import Foundation

// https://stackoverflow.com/questions/46508705/get-all-key-paths-from-a-struct-in-swift-4

extension String {
    /// Returns string without first character
    var byRemovingFirstCharacter: String {
        guard count > 1 else { return "" }
        return String(suffix(count-1))
    }
}

// MARK: - Mirror convenience extension

extension Mirror {
    
    /// Iterates through all children
    static func forEachProperty(of object: Any, doClosure: (String, Any)->Void) {
        var mirror: Mirror? = Mirror(reflecting: object)

        while let unwrappedMirror = mirror {
            for (property, value) in unwrappedMirror.children where property != nil {
                doClosure(property!, value)
            }
            mirror = mirror?.superclassMirror
        }
        
    }
    
    /// Executes closure if property named 'property' is found
    ///
    /// Returns true if property was found
    @discardableResult static func withProperty(_ property: String, of object: Any, doClosure: (String, Any)->Void) -> Bool {
        for (property, value) in Mirror(reflecting: object).children where property == property {
            doClosure(property!, value)
            return true
        }
        return false
    }
}

// MARK: - Mirror extension to return any object properties as [Property, Value] dictionary

extension Mirror {
        /// Returns objects properties as a dictionary [property: value]
    static func allKeyPaths(for object: Any) -> [String: any OcaPropertyRepresentable] {
        var out = [String: any OcaPropertyRepresentable]()
        
        Mirror.forEachProperty(of: object) { property, value in
            guard let value = value as? any OcaPropertyRepresentable else {
                return
            }
            out[property.byRemovingFirstCharacter] = value
        }
        return out
    }
}

// MARK: - KeyPathIterable protocol

protocol KeyPathIterable {
    
}

extension KeyPathIterable {
    /// Returns all object properties
    var allKeyPaths: [String: Any] {
        return Mirror.allKeyPaths(for: self)
    }
}
