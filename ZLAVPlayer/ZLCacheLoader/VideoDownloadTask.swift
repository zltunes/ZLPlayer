//
//  VideoDownloadTask.swift
//  ZLAVPlayer
//
//  Created by 赵磊 on 2018/7/12.
//  Copyright © 2018年 zl. All rights reserved.
//

import Foundation
import AVFoundation

// 下载进度回调
typealias VideoDownloadProgressHandler = ((AVAssetResourceLoadingRequest?, VideoDownloadTask) -> Void)

// 下载完成回调
typealias VideoDownloadCompleteHandler = ((Data?, Error?) -> Void)


/**
    视频下载回调结构
 */
class VideoDownloadCallback {

    /// 视频播放器加载request
    let loadingRequest: AVAssetResourceLoadingRequest?

    /// 进度回调
    let progressHandler: VideoDownloadProgressHandler?

    /// 完成回调
    let completeHandler: VideoDownloadCompleteHandler?

    init?(loadingRequest: AVAssetResourceLoadingRequest? = nil, progress: VideoDownloadProgressHandler? = nil, complete: VideoDownloadCompleteHandler? = nil) {
        if loadingRequest == nil && progress == nil && complete == nil  {
            return nil
        }
        
        self.loadingRequest = loadingRequest
        self.progressHandler = progress
        self.completeHandler = complete
    }
}

/**
    视频下载任务
 */
class VideoDownloadTask {

    /// 下载url
    let url: URL

    /// 下载任务
    let dataTask: URLSessionDataTask

    private var observers = [WeakObject<VideoResourceLoader>]()
    private let observersLock = NSLock()

    /// 回调
    lazy var callbacks = [VideoDownloadCallback]()
    private let callbacksLock = NSLock()

    /// 视频data
    var cachedData: Data {
        dataLock.lock()
        defer {
            dataLock.unlock()
        }

        let dataCopy = data
        return dataCopy
    }
    private lazy var data = Data()
    private let dataLock = NSLock()

    /// 视频总长度
    var contentLength = 0

    /// 通过URL和DataTask初始化
    init(url: URL, dataTask: URLSessionDataTask) {
        self.url = url
        self.dataTask = dataTask
    }

    /// 添加data
    func appendData(_ newData: Data) {
        dataLock.lock()
        if newData.count > 0 {
            data.append(newData)
        }
        dataLock.unlock()
    }

    /// 添加回调
    func addCallback(_ callback: VideoDownloadCallback) {
        callbacksLock.lock()
        callbacks.append(callback)
        callbacksLock.unlock()
    }

    /// 移除回调
    func removeCallback(by loadingRequest: AVAssetResourceLoadingRequest) {
        callbacksLock.lock()

        if callbacks.count > 0{
            callbacks = callbacks.filter{ task -> Bool in
                return task.loadingRequest != loadingRequest
            }
        }

        callbacksLock.unlock()
    }

    /// 添加观察者
    func addObsever(_ obsever: WeakObject<VideoResourceLoader>) {
        if obsever.target == nil {
            return
        }

        observersLock.lock()
        observers = observers.filter { return $0.target != nil}
        if !observers.contains { $0.target == obsever.target} {
            observers.append(obsever)
        }
        observersLock.unlock()
    }

    /// 移除观察者
    func removeObsever(_ obsever: WeakObject<VideoResourceLoader>) {
        observersLock.lock()
        observers = observers.filter { return $0.target != nil && $0.target != obsever.target}
        observersLock.unlock()
    }

    /// 过滤空的obsever，返回当前的数量
    func filterNullObsever() -> Int {
        observersLock.lock()
        observers = observers.filter { return $0.target != nil}
        observersLock.unlock()
        return observers.count
    }
}

// MARK: - VideoDownloadTask Equatable
extension VideoDownloadTask: Equatable {

    static func == (lhs: VideoDownloadTask, rhs: VideoDownloadTask) -> Bool {
        return lhs.url == rhs.url
    }
}
