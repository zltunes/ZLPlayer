//
//  VideoLoaderManager.swift
//  Video
//
//  Created by 赵磊 on 2018/6/15.
//  Copyright © 2018年 zl. All rights reserved.
//

import UIKit
import AVFoundation
import MobileCoreServices

/**
      AVPlayer播放器下载代理
 */
class VideoResourceLoader: NSObject {

    /// 加载队列
    let resourceLoaderQueue = DispatchQueue(label: "resourceLoaderQueue")
    
    /// 原始url
    let originalURL: URL
    
    init(originalURL: URL) {
        self.originalURL = originalURL
        
        super.init()
    }
    
    deinit {
        // 取消并保存数据
        let url = originalURL
        DispatchQueue.global().async { // 防止锁逻辑卡到主线程，cancel放到子线程去做
            VideoDownloadManager.shared.cancelDownload(url: url)
        }
    }
    
    /// 填充数据
    @discardableResult
    private func respondData(loadingRequest: AVAssetResourceLoadingRequest, data: Data, dataOffset: Int, contentLength: Int, mimeType: String) -> Bool {
        if loadingRequest.isCancelled || loadingRequest.isFinished {
            return false
        }
        // 填充信息
        if let contentInformationRequest = loadingRequest.contentInformationRequest {
            let contentType =  UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimeType as CFString, nil)?.takeRetainedValue()
            contentInformationRequest.contentType = contentType as String?
            contentInformationRequest.isByteRangeAccessSupported = true
            contentInformationRequest.contentLength = Int64(contentLength)
        }

        // 填充数据
        if let dataRequest = loadingRequest.dataRequest {
            guard dataRequest.currentOffset >= dataOffset && dataRequest.currentOffset < dataOffset.advanced(by: data.count) else {
                return false // 没有可用数据
            }
            
            // 可用cache长度
            let availableCacheLength = dataOffset.advanced(by: data.count).advanced(by: Int(-dataRequest.currentOffset))
            // 待填充数据长度
            let requestedEndIndex = (dataRequest.requestsAllDataToEndOfResource ? contentLength : Int(dataRequest.requestedOffset.advanced(by: dataRequest.requestedLength)))
            let unreadLength = requestedEndIndex.advanced(by: Int(-dataRequest.currentOffset))
            // 填充数据长度
            let respondDataLength = min(availableCacheLength, Int(unreadLength))
            
            // 进行数据填充
            let beginIndex = dataRequest.currentOffset.advanced(by: -dataOffset)
            let endIndex = beginIndex.advanced(by: respondDataLength)
//            print("respondData \(beginIndex)-\(endIndex) totalCacheLength:\(data.count) dataOffset:\(dataOffset)")
            let respondData = data.subdata(in: Int(beginIndex)..<Int(endIndex))
            dataRequest.respond(with: respondData)
            
            // 判断是否结束
            if dataRequest.currentOffset >= dataRequest.requestedOffset.advanced(by: dataRequest.requestedLength) {
                print("\(#function)  finishLoading")
                loadingRequest.finishLoading()
                return true
            }
        }

        return false
    }
}


// MARK: - AVAssetResourceLoaderDelegate
extension VideoResourceLoader: AVAssetResourceLoaderDelegate {
    
    public func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        print("resourceLoader|shouldWaitForLoadingOfRequestedResource  requestedOffset:\(String(describing: loadingRequest.dataRequest?.requestedOffset)) requestedLength:\(String(describing: loadingRequest.dataRequest?.requestedLength)) currentOffset:\(String(describing: loadingRequest.dataRequest?.currentOffset))")

        // 启动下载任务，同时保留loadingRequest, progress 是 URLSession 响应数据的回调处理
        VideoDownloadManager.shared.startDownload(url: originalURL, loadingRequest: loadingRequest, progress: { [weak self] (loadingRequest, task) in
            if nil  == self {
                return
            }
            
            self!.resourceLoaderQueue.async { [weak self] in
                if nil  == self {
                    return
                }

                let isFinish = self!.respondData(loadingRequest: loadingRequest!, data: task.cachedData, dataOffset: 0, contentLength: task.contentLength, mimeType: "video/mp4")
                if isFinish {
                    task.removeCallback(by: loadingRequest!)
                }
            }
        }, complete: {  _,_  in

        }, observer: self)

        return true
    }
    
    public func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        print("resourceLoader|didCancel")
        
        VideoDownloadManager.shared.cancelDownloadCallback(url: originalURL, loadingRequest: loadingRequest)
    }
}


