//
//  VideoDownloadManager.swift
//  ZLAVPlayer
//
//  Created by 赵磊 on 2018/7/12.
//  Copyright © 2018年 zl. All rights reserved.
//

import Foundation
import AVFoundation

fileprivate let kURLTaskSemaphore = DispatchSemaphore(value: 1)


/**
    视频下载管理类
 */
class VideoDownloadManager: NSObject {

    static let shared = VideoDownloadManager()

    /// 存放下载任务的字典
    private lazy var urlTasks = [URL: VideoDownloadTask]()

    private var session: URLSession!

    private var downloadQueue: DispatchQueue!

    private override init() {
        super.init()

        downloadQueue = DispatchQueue(label: "VideoDownloadQueue")

        let opertionQueue = OperationQueue()
        opertionQueue.maxConcurrentOperationCount = 3
        opertionQueue.underlyingQueue = downloadQueue
        session = URLSession(configuration: .default, delegate: self, delegateQueue: opertionQueue)
    }

    /// 启动下载任务
    func startDownload(url: URL, loadingRequest: AVAssetResourceLoadingRequest?, progress: VideoDownloadProgressHandler?, complete: VideoDownloadCompleteHandler?, observer: VideoResourceLoader? = nil) {
        _ = kURLTaskSemaphore.wait(timeout: .distantFuture)

        // 已经存在任务
        if let task = urlTasks[url] {
            if let loadingRequest = loadingRequest {
                print("Video|download", "start| exist task | url: \(url)")

                /// 添加回调
                if let callback = VideoDownloadCallback(loadingRequest: loadingRequest, progress: progress, complete: complete) {
                    task.addCallback(callback)
                }

                /// 添加观察者
                if let observer = observer {
                    let weakObject = WeakObject<VideoResourceLoader>(target: observer)
                    task.addObsever(weakObject)
                }

                // 回调上层
                if let progress = progress {
                    progress(loadingRequest, task)
                }
            }

            kURLTaskSemaphore.signal()
        } else { // 创建任务
            // 框架支持部分缓存，当视频还未缓冲完 playerItem 即被销毁时，将本次已下载数据缓存起来
            // 新的 task 先异步载入缓存再继续下载，从而实现“断点续传”
            VideoCacheManager.shared.asynLoadCache(url: url) { (data, contentLength) in
                let cacheLength = (data != nil) ? data!.count : 0
                let isFullCache = (cacheLength > 0 && data!.count == contentLength!)

                print("Video|download", "start| new task| cacheLength:\(cacheLength) isFullCache:\(isFullCache)| url: \(url)")

                // 创建下载任务
                let request = self.createURLRequest(url: url, loadingRequest: (isFullCache ? nil : loadingRequest), cacheLength: cacheLength)
                let dataTask = self.session.dataTask(with: request)
                let newTask = VideoDownloadTask(url: url, dataTask: dataTask)

                /// 添加回调
                if let callback = VideoDownloadCallback(loadingRequest: loadingRequest, progress: progress, complete: complete) {
                    newTask.addCallback(callback)
                }

                /// 添加观察者
                if let observer = observer {
                    // 注意：newTask 维护一个 observers 数组，对每个 observer（resourceLoader） 都是强引用
                    // 避免内存泄漏，使用一个弱引用对象容器封装
                    let weakObject = WeakObject<VideoResourceLoader>(target: observer)
                    newTask.addObsever(weakObject)
                }

                // 填充缓存的数据
                if let data = data {
                    newTask.contentLength = contentLength!
                    newTask.appendData(data)

                    // 回调上层
                    if let loadingRequest = loadingRequest, let progress = progress {
                        progress(loadingRequest, newTask)
                    }
                }

                self.urlTasks[url] = newTask

                // 任务启动
                if !isFullCache {
                    dataTask.resume()
                }

                kURLTaskSemaphore.signal()
            }
        }
    }

    /// 启动下载任务
    func preDownload(url: URL) {
        if let _ = VideoCacheManager.existVideoFilePath(url: url) {
            print("Video|download", "preload| video is cached| url: \(url)")
            return
        }

        print("Video|download", "preload| url: \(url)")

        // 防止锁逻辑卡到主线程，preDownload放到子线程去做
        DispatchQueue.global().async {
            self.startDownload(url: url, loadingRequest: nil, progress: nil, complete: nil)
        }
    }

    /// 删除下载（包括缓存，用于重试的场景）
    func removeDownload(url: URL, completion: (() -> Void)?) {
        _ = kURLTaskSemaphore.wait(timeout: .distantFuture)

        print("Video|download", "remove|url: \(url)")

        // 取消下载
        if let downloadTask = self.urlTasks[url] {
            self.urlTasks.removeValue(forKey: url)
            downloadTask.dataTask.cancel()
        }

        // 删除缓存
        VideoCacheManager.shared.removeCache(url: url, completion: completion)

        kURLTaskSemaphore.signal()
    }

    /// 取消请求
    func cancelDownload(url: URL, observer: VideoResourceLoader? = nil) {
        _ = kURLTaskSemaphore.wait(timeout: .distantFuture)

        // 存在任务
        if let downloadTask = self.urlTasks[url] {
            var shouldCancel = false
            if let observer = observer {
                downloadTask.removeObsever(WeakObject<VideoResourceLoader>(target: observer))
            }

            let restCount = downloadTask.filterNullObsever()
            if restCount == 0 {
                shouldCancel = true // 任务还有其它观察者
            } else {
                print("Video|download", "cancel|fail|restCount:\(restCount)|taskCount:\(self.urlTasks.count)|url: \(url)")
            }

            if shouldCancel {
                print("Video|download", "cancel|success|taskCount:\(self.urlTasks.count)|url: \(url)")

                self.urlTasks.removeValue(forKey: url)
                downloadTask.dataTask.cancel()
                VideoCacheManager.shared.storeCache(with: downloadTask, completion: nil)
            }
        } else { // 不存在任务
            print("Video|download", "cancel|not exist|taskCount:\(self.urlTasks.count)|url: \(url)")
        }

        kURLTaskSemaphore.signal()
    }

    /// 取消请求
    func cancelDownloadCallback(url: URL, loadingRequest: AVAssetResourceLoadingRequest) {
        _ = kURLTaskSemaphore.wait(timeout: .distantFuture)

        if let downloadTask = self.urlTasks[url] {
            downloadTask.removeCallback(by: loadingRequest)
        }

        kURLTaskSemaphore.signal()
    }

    /// 创建下载URL请求
    private func createURLRequest(url: URL, loadingRequest: AVAssetResourceLoadingRequest?, cacheLength: Int) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        // 设置Range, 如果有部分本地缓存，将缓存终点作为本次请求起点
        if let dataRequest = loadingRequest?.dataRequest {
            let requestedOffset = (cacheLength > 0 ? Int64(cacheLength) : dataRequest.requestedOffset)
            request.addValue("bytes=\(requestedOffset)-", forHTTPHeaderField: "Range")
        }

        return request
    }

    /// 根据dataTask查找对应的下载任务
    private func downloadTask(for dataTask: URLSessionDataTask) -> VideoDownloadTask? {
        _ = kURLTaskSemaphore.wait(timeout: .distantFuture)
        defer {
            kURLTaskSemaphore.signal()
        }

        for (_, task) in urlTasks {
            if task.dataTask.taskIdentifier == dataTask.taskIdentifier {
                return task
            }
        }

        return nil
    }
}


// MARK: - URLSessionDataDelegate
extension VideoDownloadManager: URLSessionDataDelegate {
    
    /// 从响应请求头中获取视频文件总长度 contentLength
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let downloadTask = downloadTask(for: dataTask) {
            guard response.mimeType == "video/mp4" else {
//                print("Video|download", "didReceiveResponse|\(dataTask.taskIdentifier)|errorCode:\((response as! HTTPURLResponse).statusCode) mimeType:\(String(describing: response.mimeType)) | url:\(downloadTask.url)")
                return
            }
            
            // 请求头有两个字段需要关注
            // Content-Length表示本次请求的数据长度
            // Content-Range表示本次请求的数据在总媒体文件中的位置，格式是start-end/total，因此就有Content-Length = end - start + 1。

            if let contentRange = (response as! HTTPURLResponse).allHeaderFields["Content-Range"] as? String {
                let contentLengthString = contentRange.split(separator: "/").map{String($0)}.last!
                downloadTask.contentLength = Int(contentLengthString)!
            } else {
                downloadTask.contentLength = Int(response.expectedContentLength)
            }

//            print("Video|download", "didReceiveResponse \(dataTask.taskIdentifier) contentLength:\(downloadTask.contentLength)| url:\(downloadTask.url)")
        }

        completionHandler(.allow)
    }

     /// 收到响应数据的处理
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let downloadTask = downloadTask(for: dataTask) {
//            print("Video|download", "\(#function) \(dataTask.taskIdentifier) total:\(downloadTask.contentLength) cacheLength:\(downloadTask.cachedData.count) newLength:\(data.count)")
            
            // 在已下载数据基础上填充
            downloadTask.appendData(data)

            let callbacks = downloadTask.callbacks
            for callback in callbacks {
                if let progress = callback.progressHandler {
                    progress(callback.loadingRequest, downloadTask)
                }
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let downloadTask = downloadTask(for: task as! URLSessionDataTask) {
            if let error = error as NSError? {
                print("Video|download", "finish|fail|\(task.taskIdentifier) errorCode:\(error.code) \(error.localizedDescription) total:\(downloadTask.contentLength) cacheLength:\(downloadTask.cachedData.count)| url:\(downloadTask.url)")
            } else {
                print("Video|download", "finish|success|\(task.taskIdentifier) total:\(downloadTask.contentLength) cacheLength:\(downloadTask.cachedData.count)| url:\(downloadTask.url)")
            }

            // 移除任务
            _ = kURLTaskSemaphore.wait(timeout: .distantFuture)

            let callbacks = downloadTask.callbacks
            for callback in callbacks {
                if let complete = callback.completeHandler {
                    complete(downloadTask.cachedData, error)
                }
            }

            VideoCacheManager.shared.storeCache(with: downloadTask, completion: {
                DispatchQueue.global().async { // 异步跳出cache的io队列，防止死锁
                    _ = kURLTaskSemaphore.wait(timeout: .distantFuture)

                    let restCount = downloadTask.filterNullObsever()
                    if restCount == 0 {
                        self.urlTasks.removeValue(forKey: downloadTask.url)
                        print("Video|download", "finish|remove task|taskCount:\(self.urlTasks.count)|url: \(downloadTask.url)")
                    }

                    kURLTaskSemaphore.signal()
                }
            })

            kURLTaskSemaphore.signal()
        }
    }
}
