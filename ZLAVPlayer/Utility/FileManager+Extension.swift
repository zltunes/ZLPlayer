//
//  FileManager+Extension.swift
//  ZLAVPlayer
//
//  Created by 赵磊 on 2018/7/10.
//  Copyright © 2018年 zl. All rights reserved.
//

import Foundation

extension FileManager {
    
    /// Documents路径
    static let documentsPath: String = {
        let array = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        return array.first!
    }()

    /// 获取Users Documents目录
    static let usersDocumentsPath: String? = {
        let usersDocumentsPath = FileManager.documentsPath.appendingPathComponent("Users")
        guard createPath(path: usersDocumentsPath) else {
            return nil
        }

        return usersDocumentsPath
    }()
    
    /// Caches路径
    static let cachesPath: String = {
        let array = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)
        return array.first!
    }()
    
    /// 获取Users Cache目录
    static let usersCachePath: String? = {
        let usersCachePath = FileManager.cachesPath.appendingPathComponent("Users")
        guard createPath(path: usersCachePath) else {
            return nil
        }
        
        return usersCachePath
    }()
    
//    /// 获取当前用户的Cache目录
//    static let currentUserCachePath: String? = {
//        guard let usersCachePath = usersCachePath else {
//            return nil
//        }
//
//        var currentUserCachePath: String
//        let userID = AccountManager.shared.accountInfo.userID
//        if userID.count > 0 {
//            currentUserCachePath = usersCachePath.appendingPathComponent(userID)
//        }
//        else {
//            currentUserCachePath = usersCachePath.appendingPathComponent(AppCommon.deviceID)
//        }
//
//        guard createPath(path: currentUserCachePath) else {
//            return nil
//        }
//
//        return currentUserCachePath
//    }()
//
//    /// 生成当前用户目录下特定模块的缓存文件
//    static func buildCacheFile(module: String..., name: String) -> String? {
//        guard let currentUserCachePath = FileManager.currentUserCachePath else {
//            return nil
//        }
//
//        var modulePath = currentUserCachePath
//        for moduleItem in module {
//            modulePath = modulePath.appendingPathComponent(moduleItem)
//
//            guard createPath(path: modulePath) else {
//                return nil
//            }
//        }
//
//        let cacheFilePath = modulePath.appendingPathComponent(name)
//
//        guard createFile(file: cacheFilePath) else {
//            return nil
//        }
//
//        return cacheFilePath
//    }
    
    /// 创建目录
    static func createPath(path: String) -> Bool {
        var success = true
        
        if !FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                success = false
                print("FileManager", "create path=\(path) error:\(error)")
            }
        }
        
        return success
    }
    
    ///  创建文件
    static func createFile(file: String) -> Bool {
        if !FileManager.default.fileExists(atPath: file) {
            return FileManager.default.createFile(atPath: file, contents: nil, attributes: nil)
        }
        
        return true
    }
}

extension String {
    
    /// lastPathComponent
    var lastPathComponent: String {
        return (self as NSString).lastPathComponent
    }
    
    /// deletingLastPathComponent
    var deletingLastPathComponent: String {
        return (self as NSString).deletingLastPathComponent
    }
    
    /// appendingPathComponent
    func appendingPathComponent(_ str: String) -> String {
        return (self as NSString).appendingPathComponent(str)
    }
}
