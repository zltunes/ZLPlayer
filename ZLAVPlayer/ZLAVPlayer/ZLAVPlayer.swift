//
//  ZLAVPlayer.swift
//  ZLAVPlayer
//
//  Created by 赵磊 on 2019/4/16.
//  Copyright © 2019 zl. All rights reserved.
//

import UIKit
import Foundation
import AVFoundation

typealias ProgressHandler = ((_ player: ZLAVPlayer, _ progress: Double) -> Void)  //视频播放进度回调
typealias SeekCompleteHandler = ((_ player: ZLAVPlayer, _ prePos: Double, _ curtPos: Double) -> Void) //视频 seek 完成
typealias WillSeekToPosition = ((_ player: ZLAVPlayer, _ curtPos: Double, _ toPos: Double) -> Void) //视频即将 seek
typealias CompleteHandler = ((_ player: ZLAVPlayer) -> Void) //视频播放完成
typealias ErrorHandler = ((_ player: ZLAVPlayer, _ error: Error?) -> Void) //播放错误
typealias LoadStatusHandler = ((_ player: ZLAVPlayer, _ status: AVPlayerItem.Status) -> Void) //流媒体加载状态
typealias BufferPercentHandler = ((_ player: ZLAVPlayer, _ bufferPercent: Double) -> Void) //流媒体缓冲百分比
typealias BufferingHandler = ((_ player: ZLAVPlayer) -> Void) //正在缓冲
typealias BufferFinishHandler = ((_ player: ZLAVPlayer) -> Void) //缓冲结束

protocol ZLAVPlayerDelegate: class{
    func player(_ player: ZLAVPlayer?, progress: Double)
    func playerWillSeek(toPosition player: ZLAVPlayer?, curtPos: Double, toPos: Double)
    func playerSeekComplete(_ player: ZLAVPlayer?, prePos: Double, curtPos: Double)
    func playerComplete(_ player: ZLAVPlayer?)
    func playerBuffering(_ player: ZLAVPlayer?)
    func playerBufferFinish(_ player: ZLAVPlayer?)
    func player(_ player: ZLAVPlayer?, error: Error?)
    func player(_ player: ZLAVPlayer?, load status: AVPlayerItem.Status)
    func player(_ player: ZLAVPlayer?, bufferPercent: Double)

}

class ZLAVPlayer: NSObject {
    
    var mediaUrl: String! //视频地址
    private var player: AVPlayer?   //播放器实例
    var playerLayer: AVPlayerLayer? //视频渲染图层
    var playerItem: AVPlayerItem? //媒体资源
    private var playTimeObserverToken: Any?
    private var videoResourceLoader: VideoResourceLoader? //视频下载代理
    
    private var totalBuffer: Double? //缓冲长度
    var currentPlayTime: Double? //当前播放时间
    var totalTime: Double? //总时长
    private var curtPosition: Double? //当前播放位置
    private var seekToPosition: Double? //seek播放位置
    
    private var retryCount: Int = 2 //重加载次数
    
    var progressHandler: ProgressHandler?
    var seekCompleteHandler: SeekCompleteHandler?
    var willSeekToPosition: WillSeekToPosition?
    var completeHandler: CompleteHandler?
    var errorHandler: ErrorHandler?
    var loadStatusHandler: LoadStatusHandler?
    var bufferPercentHandler: BufferPercentHandler?
    var bufferingHandler: BufferingHandler?
    var bufferFinishHandler: BufferFinishHandler?
    weak var delegate: ZLAVPlayerDelegate?
    
    init(withURL url: String?,
         process:ProgressHandler?,
         compelete: CompleteHandler?,
         loadStatus: LoadStatusHandler?,
         bufferPercent: BufferPercentHandler?,
         willSeek: WillSeekToPosition?,
         seekComplete: SeekCompleteHandler?,
         buffering: BufferingHandler?,
         bufferFinish: BufferFinishHandler?,
         error: ErrorHandler?) {
        
        super.init()
        initPlayEnv()
        
        mediaUrl = url
        progressHandler = process
        completeHandler = compelete
        loadStatusHandler = loadStatus
        bufferPercentHandler = bufferPercent
        willSeekToPosition = willSeek
        seekCompleteHandler = seekComplete
        bufferingHandler = buffering
        bufferFinishHandler = bufferFinish
        errorHandler = error
        
        preparePlayer()
    }
    
    private func preparePlayer() {
        guard let url = URL(string: mediaUrl) else {
            return
        }
        
        if player != nil {
            removeProgressObserver()
            removeObserver(from: playerItem)
            removeNotification()
        }
        
        currentPlayTime = 0
        totalTime = 0
        
        if let filePath = VideoCacheManager.existVideoFilePath(url: url) {
            //本地缓存
            playerItem = AVPlayerItem(url: URL(fileURLWithPath: filePath))
        } else {
            //下载
            let urlAssrt = AVURLAsset(url: url.streamSchemeURL)
            videoResourceLoader = VideoResourceLoader(originalURL: url)
            urlAssrt.resourceLoader.setDelegate(videoResourceLoader, queue: videoResourceLoader?.resourceLoaderQueue)
            playerItem = AVPlayerItem(asset: urlAssrt)
        }
        
        if player == nil {
            player = AVPlayer()
            playerLayer?.removeFromSuperlayer()
            playerLayer = AVPlayerLayer(player: player)
            //设置拉伸模式
            playerLayer?.videoGravity = .resizeAspect
            playerLayer?.contentsScale = UIScreen.main.scale
            player?.replaceCurrentItem(with: playerItem)
            
        } else {
            player?.replaceCurrentItem(with: playerItem)
        }
        
        addProgressObserver()
        addObserver(to: playerItem)
        addNotification()
    }
    
    deinit {
        removeProgressObserver()
        removeObserver(from: playerItem)
        removeNotification()
    }
    
    private func initPlayEnv() {
        //app进入后台
        NotificationCenter.default.addObserver(self, selector: #selector(self.appResignActive(_:)), name: UIApplication.willResignActiveNotification, object: nil)
        //app进入前台
        NotificationCenter.default.addObserver(self, selector: #selector(self.appBecomeActive(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
        
        // 监听耳机插入和拔掉通知
        NotificationCenter.default.addObserver(self, selector: #selector(self.audioRouteChangeListenerCallback(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        //中断处理(播放过程中有打电话等系统事件)
        NotificationCenter.default.addObserver(self, selector: #selector(self.handleInterruption(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        do {
            try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback /*允许后台*/, options: .mixWithOthers /*混合播放，不独占*/)
        } catch {
        }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
        }

    }
}

// MARK:- 播放对象的状态、播放进度监控
extension ZLAVPlayer {
    
    /// ------------------------------------- 状态监控 --------------------------------------------------
    /**
     *  给AVPlayerItem添加监控
     *
     *  @param playerItem AVPlayerItem对象
     */
    func addObserver(to playerItem: AVPlayerItem?) {
        if playerItem != nil {
            //监控播放状态
            playerItem?.addObserver(self, forKeyPath: "status", options: .new, context: nil)
            //监控网络加载情况
            playerItem?.addObserver(self, forKeyPath: "loadedTimeRanges", options: .new, context: nil)
            //正在缓冲
            playerItem?.addObserver(self, forKeyPath: "playbackBufferEmpty", options: .new, context: nil)
            //缓冲结束
            playerItem?.addObserver(self, forKeyPath: "playbackLikelyToKeepUp", options: .new, context: nil)
        }
    }
    
    func removeObserver(from playerItem: AVPlayerItem?) {
        var playerItem = playerItem
        if playerItem != nil {
            playerItem?.removeObserver(self, forKeyPath: "status")
            playerItem?.removeObserver(self, forKeyPath: "loadedTimeRanges")
            playerItem?.removeObserver(self, forKeyPath: "playbackBufferEmpty")
            playerItem?.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp")
            playerItem = nil
        }
    }
    
    /**
     *  通过KVO监控播放器状态
     *
     *  @param keyPath 监控属性
     *  @param object  监视器
     *  @param change  状态改变
     *  @param context 上下文
     */
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let playerItem = object as? AVPlayerItem else {
            return
        }
        
        if keyPath == "status" {
            switch playerItem.status {
            case .unknown:
                print("加载状态：未知状态，此时不能播放")
            case .readyToPlay:
                totalTime = playerItem.asset.duration.seconds
                print("加载状态：准备完毕，可以播放，总时长\(String(describing: totalTime))")
            case .failed:
                print("加载状态：加载失败，网络或者服务器出现问题: \(String(describing: playerItem.error))")
                if retryCount > 0 {
                    retryCount -= 1
                    VideoDownloadManager.shared.removeDownload(url: URL(string: mediaUrl)!) {
                        DispatchQueue.main.async { [weak self] in
                            self?.preparePlayer()
                        }
                    }
                    return
                }

            default:
                break
            }
            
            if let loadStatusHandler = loadStatusHandler {
                loadStatusHandler(self, playerItem.status)
            }
            if let delegate = delegate {
                delegate.player(self, load: playerItem.status)
            }
            
        } else if keyPath == "loadedTimeRanges" {
            let ranges = playerItem.loadedTimeRanges
            let range = ranges.first?.timeRangeValue //本次缓冲时间范围
            totalBuffer = range!.start.seconds + range!.duration.seconds //缓冲总长度
            if let bufferPercentHandler = bufferPercentHandler {
                bufferPercentHandler(self, totalBuffer! / playerItem.asset.duration.seconds)
            }
            if let delegate = delegate {
                 delegate.player(self, bufferPercent: totalBuffer! / playerItem.asset.duration.seconds)
            }
        
        } else if keyPath == "playbackBufferEmpty" {
            if let bufferingHandler = bufferingHandler {
                bufferingHandler(self)
            }
            if let delegate = delegate {
                delegate.playerBuffering(self)
            }
            
        } else if keyPath == "playbackLikelyToKeepUp" {
            if let bufferFinishHandler = bufferFinishHandler {
                bufferFinishHandler(self)
            }
            if let delegate = delegate {
                 delegate.playerBufferFinish(self)
            }
        
        }
    }
    
    
    /// ------------------------------------- 进度监控 --------------------------------------------------
    /**
     *  给播放器添加进度更新
     */
    func addProgressObserver() {
        
        //这里设置每秒执行一次
        let playerItem: AVPlayerItem? = self.playerItem
        
        let interval = CMTime(value: 1, timescale: 5)

        playTimeObserverToken = player?.addPeriodicTimeObserver(forInterval: interval, queue: DispatchQueue.main, using: { [weak self] time in
            guard let `self` = self else {
                return
            }
            self.currentPlayTime = CMTimeGetSeconds(time)
            self.totalTime = CMTimeGetSeconds(playerItem?.duration ?? CMTime.zero)
            self.curtPosition = self.currentPlayTime! / self.totalTime!
            
            if let progress = self.progressHandler {
                progress(self, self.curtPosition ?? 0)
            }
            if let delegate = self.delegate {
                delegate.player(self, progress: self.curtPosition ?? 0)
            }
        })
    }
    
    func removeProgressObserver() {
        if let observer = playTimeObserverToken {
            player?.removeTimeObserver(observer)
        }
    }
    
    
    /// ------------------------------------- 播放完成、错误通知 --------------------------------------------------
    func addNotification() {
        //给 AVPlayerItem 添加播放完成通知
        NotificationCenter.default.addObserver(self, selector: #selector(self.playbackFinished(_:)), name: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem)
        
        //给 AVPlayerItem 添加播放错误通知
        NotificationCenter.default.addObserver(self, selector: #selector(self.playbackFail(_:)), name: .AVPlayerItemFailedToPlayToEndTime, object: player?.currentItem)
    }
    
    func removeNotification() {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func playbackFinished(_ notification: Notification?) {
        curtPosition = 0
        totalTime = 0
        currentPlayTime = totalTime
        if let complete = completeHandler {
            complete(self)
        }
        if let delegate = self.delegate {
            delegate.playerComplete(self)
        }
    }
    
    @objc func playbackFail(_ notification: Notification?) {
        curtPosition = 0
        totalTime = 0
        currentPlayTime = totalTime
        if let error = errorHandler {
            error(self, player?.error)
        }
        if let delegate = self.delegate {
            delegate.player(self, error: player?.error)
        }
    }
}

// MARK - 外部环境监控
extension ZLAVPlayer {
    
    /// ------------------------------------- app进入前后台 --------------------------------------------------
    @objc func appResignActive(_ notification: Notification?) {
        if !playFinish() {
            pause()
        }
    }
    
    @objc func appBecomeActive(_ notification: Notification?) {
        if !playFinish() {
            play()
        }
    }
    
    /// ------------------------------------- 中断处理 --------------------------------------------------
    @objc func handleInterruption(_ notification: Notification?) {
        let interruptionDictionary = notification?.userInfo
        
        let type = (interruptionDictionary?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
        
        if type == AVAudioSession.InterruptionType.ended.rawValue {
            if UIApplication.shared.applicationState == .active {
                DispatchQueue.global(qos: .default).asyncAfter(deadline: DispatchTime.now() + Double(Int64(1.0 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC), execute: {
                    if !self.playFinish() {
                        self.play()
                    }
                })
            }
        } else if type == AVAudioSession.InterruptionType.began.rawValue {
            DispatchQueue.global(qos: .default).asyncAfter(deadline: DispatchTime.now() + Double(Int64(1.0 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC), execute: {
                if !self.playFinish() {
                    self.pause()
                }
            })
        }
    }

    /// ------------------------------------- 耳机插拔事件 --------------------------------------------------
    @objc func audioRouteChangeListenerCallback(_ notification: Notification?) {
        let interuptionDict = notification?.userInfo
        
        let routeChangeReason: Int = (interuptionDict?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.intValue ?? 0
        
        switch routeChangeReason {
        case kAudioSessionRouteChangeReason_NewDeviceAvailable, kAudioSessionRouteChangeReason_OldDeviceUnavailable:
            //获取上一线路描述信息并获取上一线路的输出设备类型
            let previousRoute = interuptionDict?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
            let previousOutput = previousRoute?.outputs[0]
            let portType = previousOutput?.portType
            if (portType == .headphones) {
                DispatchQueue.global(qos: .default).asyncAfter(deadline: DispatchTime.now() + Double(Int64(1.0 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC), execute: {
                    // 这里的处理是一秒过后，继续使用手机的扬声器播放
                    if !self.playFinish() {
                        self.play()
                    }
                })
            }
        case kAudioSessionRouteChangeReason_CategoryChange:
            break
        default:
            break
        }
    }

}

// MARK - 播放控制
extension ZLAVPlayer {
    func play() {
        if player?.rate == 1.0 {
            return
        }
        player?.play()
    }
    
    func isPlay() -> Bool {
        return player?.rate == 1.0
    }
    
    func pause() {
        if player?.rate == 0.0 {
            return
        }
        player?.pause()
    }
    
    func isPause() -> Bool {
        return player?.rate == 0.0
    }
    
    func playFinish() -> Bool {
        return totalTime != nil && currentPlayTime == totalTime
    }
    
    func setSeek(to position: Double) {
        seekToPosition = position * totalTime!
        
        guard var seekToPosition = seekToPosition, let totalTime = totalTime else {
            return
        }
        
        if seekToPosition < 0 {
            seekToPosition = 0
        }
        if seekToPosition > totalTime {
            seekToPosition = totalTime
        }

        let time: CMTime = CMTimeMakeWithSeconds(seekToPosition, preferredTimescale: 600)
        
        //是否正在播放，YES ，则在seek完成之后恢复播放
        let isPlay = self.isPlay()
        pause()
        
        if let willSeekToPosition = willSeekToPosition {
            willSeekToPosition(self, curtPosition ?? 0, seekToPosition)
        }
        if let delegate = delegate {
            delegate.playerWillSeek(toPosition: self, curtPos: curtPosition ?? 0, toPos: seekToPosition)
        }
        
        player?.seek(to: time, completionHandler: { [weak self] finish in
            guard let `self` = self else {
                return
            }
            
            if finish {
                self.currentPlayTime = CMTimeGetSeconds(time)
                if let seekCompleteHandler = self.seekCompleteHandler {
                    seekCompleteHandler(self, self.curtPosition ?? 0, seekToPosition)
                }
                if let delegate = self.delegate {
                    delegate.playerSeekComplete(self, prePos: self.curtPosition ?? 0, curtPos: seekToPosition)
                }
                if isPlay {
                    self.play()
                }
            }
        })
    }

    
}
