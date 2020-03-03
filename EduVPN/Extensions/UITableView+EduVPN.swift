//
//  UITableView+EduVPN.swift
//  eduVPN
//

import UIKit

extension UITableView {
    
    func register<T: Identifiable>(type: T.Type, prefix: String = "") where T: UITableViewCell {
        register(type, forCellReuseIdentifier: prefix + type.identifier)
    }
    
    func dequeueReusableCell<T: Identifiable>(type: T.Type, for indexPath: IndexPath, prefix: String = "") -> T where T: UITableViewCell {
        return dequeueReusableCell(withIdentifier: prefix + type.identifier, for: indexPath) as! T // swiftlint:disable:this force_cast
    }
    
    func registerNib<T: Identifiable>(type: T.Type, prefix: String = "") where T: UITableViewCell {
        let nib = UINib(nibName: prefix + type.identifier, bundle: nil)
        register(nib, forCellReuseIdentifier: prefix + type.identifier)
    }
    
    func registerNib<T: Identifiable>(type: T.Type, prefix: String = "") where T: UITableViewHeaderFooterView {
        let nib = UINib(nibName: prefix + type.identifier, bundle: nil)
        register(nib, forHeaderFooterViewReuseIdentifier: prefix + type.identifier)
    }
    
    func dequeueReusableHeaderFooterView<T: Identifiable>(type: T.Type, prefix: String = "") -> T where T: UITableViewHeaderFooterView {
        return dequeueReusableHeaderFooterView(withIdentifier: prefix + type.identifier) as! T // swiftlint:disable:this force_cast
    }
}
