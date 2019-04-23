//
//  VideoCacheManager.swift
//  ZLAVPlayer
//
//  Created by 赵磊 on 2018/7/12.
//  Copyright © 2018年 zl. All rights reserved.
//

import Foundation

// 视频临时文件key
fileprivate let kDataKey            = "data"
fileprivate let kContentLengthKey   = "contentLength"

/**
    视频缓存管理类
 */
class VideoCacheManager {

    static let shared = VideoCacheManager()

    /// IO队列
    private let ioQueue: DispatchQueue

    private init() {
        ioQueue = DispatchQueue(label: "VideoCacheIOQueue")

    }

    /// 异步载入缓存
    func asynLoadCache(url: URL, completeHandler:@escaping (Data?, Int?) -> Void) {
        ioQueue.async {
            let file = VideoCacheManager.videoFilePath(url: url)
            if FileManager.default.fileExists(atPath: file) {
                var data: Data?
                do {
                    data = try Data(contentsOf: url)
                } catch {
                    print("Video|cache", "load video file error:\(error)")
                }

                if let data = data {
                    completeHandler(data, data.count)
                    return // 成功加载完整视频缓存
                }
            }

            let tmpFile = VideoCacheManager.tmpFilePath(url: url)
            if !FileManager.default.fileExists(atPath: tmpFile) {
                completeHandler(nil, nil)
                return
            }

            if let tmpInfo = NSKeyedUnarchiver.unarchiveObject(withFile: tmpFile) as? [String: Any] {
                if let data = tmpInfo[kDataKey] as? Data,
                    let contentLength = tmpInfo[kContentLengthKey] as? Int {
                    completeHandler(data, contentLength)
                    return
                } else {
                    print("Video|cache", "video tmp file data invalid")
                }
            } else {
                print("Video|cache", "load video tmp file data fail")
            }

            do  {
                try FileManager.default.removeItem(atPath: tmpFile)
            } catch {
                print("Video|cache", "remove video tmp file error:\(error)")
            }

            completeHandler(nil, nil)
        }
    }

    /// 保存视频缓存
    func storeCache(with downloadTask: VideoDownloadTask, completion: (() -> Void)?) {
        ioQueue.async {
            if !FileManager.default.fileExists(atPath: VideoCacheManager.videoDirectory) {
                do {
                    try FileManager.default.createDirectory(atPath: VideoCacheManager.videoDirectory, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    print("Video|cache", "create video Directory error:\(error)")
                }
            }

            let url = downloadTask.url
            let tmpFile = VideoCacheManager.tmpFilePath(url: url)

            // 保存完整视频
            let data = downloadTask.cachedData
            let contentLength = downloadTask.contentLength
            let isFinished = (data.count == contentLength)
            if isFinished {
                let file = VideoCacheManager.videoFilePath(url: url)
                do {
                    try data.write(to: URL(fileURLWithPath: file))
                } catch {
                    print("Video|cache", "store video error:\(error)")
                }

                if FileManager.default.fileExists(atPath: tmpFile) {
                    do  {
                        try FileManager.default.removeItem(atPath: tmpFile)
                    } catch {
                        print("Video|cache", "remove video tmp file error:\(error)")
                    }
                }
            } else { // 保存临时视频信息
                let tmpInfo = [kDataKey: data, kContentLengthKey: contentLength] as [String : Any]
                let success = NSKeyedArchiver.archiveRootObject(tmpInfo, toFile: tmpFile)
                if !success {
                    print("Video|cache", "store video tmp file error")
                }
            }

            completion?()
        }
    }

    /// 删除缓存
    func removeCache(url: URL, completion: (() -> Void)?) {
        ioQueue.async {
            // 临时文件
            let tmpFile = VideoCacheManager.tmpFilePath(url: url)
            if FileManager.default.fileExists(atPath: tmpFile) {
                do  {
                    try FileManager.default.removeItem(atPath: tmpFile)
                } catch {
                    print("Video|cache", "remove video tmp file error:\(error)")
                }
            }

            // 完整文件
            let file = VideoCacheManager.videoFilePath(url: url)
            if FileManager.default.fileExists(atPath: file) {
                do  {
                    try FileManager.default.removeItem(atPath: file)
                } catch {
                    print("Video|cache", "remove video file error:\(error)")
                }
            }

            completion?()
        }
    }
}

// MARK: - Resource Path
extension VideoCacheManager {

    /// 视频目录
    // /var/mobile/Containers/Data/Application/B78CD5EE-540B-4C6E-8B49-47EE148881AE/Library/Caches/videos
    static var videoDirectory: String = FileManager.cachesPath.appendingPathComponent("videos")

    /// 视频文件名(url md5值)
    static func videoFileName(url: URL) -> String {
        return url.absoluteString.md5String
    }

    /// 视频文件是否存在
    static func existVideoFilePath(url: URL) -> String? {
        let path = videoFilePath(url: url)
        if FileManager.default.fileExists(atPath:path) {
            return path
        }

        return nil
    }

    /// 视频文件路径
    static func videoFilePath(url: URL) -> String {
        let videoName = videoFileName(url: url)
        return videoDirectory.appendingPathComponent(videoName) + ".mp4"
    }

    /// 视频临时文件是否存在
    static func isTmpFileExist(url: URL) -> Bool {
        let path = tmpFilePath(url: url)
        return FileManager.default.fileExists(atPath:path)
    }

    /// 视频临时文件路径
    static func tmpFilePath(url: URL) -> String {
        let videoName = videoFileName(url: url)
        return videoDirectory.appendingPathComponent(videoName) + ".tmp"
    }
}
