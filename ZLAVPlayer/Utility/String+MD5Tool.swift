//
//  String+MD5.swift
//  Video
//
//  Created by 赵磊 on 2018/6/20.
//  Copyright © 2018年 zl. All rights reserved.
//

import Foundation


extension String {

    /// md5值
    var md5String: String {
        return withCString { (ptr: UnsafePointer<Int8>) -> String in
            var buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(CC_MD5_DIGEST_LENGTH))
            defer {
                buffer.deallocate()
            }
            
            CC_MD5(UnsafeRawPointer(ptr), CC_LONG(lengthOfBytes(using: .utf8)), buffer)
            
            var hash = String()
            for i in 0..<Int(CC_MD5_DIGEST_LENGTH) {
                hash.append(String(format: "%02x", buffer[i]))
            }
            
            return hash
        }
    }

    func subString(to index: Int) -> String {
        return String(self[..<self.index(self.startIndex, offsetBy: index)])
    }

    func subString(from index: Int) -> String {
        return String(self[self.index(self.startIndex, offsetBy: index)...])
    }

    func toRange(_ range: NSRange) -> Range<String.Index>? {
        guard let from16 = utf16.index(utf16.startIndex, offsetBy: range.location, limitedBy: utf16.endIndex) else { return nil }
        guard let to16 = utf16.index(from16, offsetBy: range.length, limitedBy: utf16.endIndex) else { return nil }
        guard let from = String.Index(from16, within: self) else { return nil }
        guard let to = String.Index(to16, within: self) else { return nil }
        return from ..< to
    }
}
