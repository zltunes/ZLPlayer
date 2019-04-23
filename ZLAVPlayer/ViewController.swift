//
//  ViewController.swift
//  ZLAVPlayer
//
//  Created by 赵磊 on 2019/4/16.
//  Copyright © 2019 zl. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    private var zlAVPlayer: ZLAVPlayer!
    private var url = "http://mirror.aarnet.edu.au/pub/TED-talks/911Mothers_2010W-480p.mp4"
    private var manualyPause = false
    
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var currentTimeLabel: UILabel!
    @IBOutlet weak var totalTimeLabel: UILabel!
    @IBOutlet weak var textview: UITextView!
    @IBOutlet weak var bufferLabel: UILabel!
    @IBOutlet weak var bufferView: UIProgressView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        zlAVPlayer = ZLAVPlayer(withURL: url,
                                process: { [weak self] (player, progress) in
                                    self?.progressView.progress = Float(progress)
                                    self?.currentTimeLabel.text = self?.timeStringFromSeconds(seconds: player.currentPlayTime ?? 0)
                                }, compelete: { [weak self] (player) in
                                    self?.textview.text = "播放结束\n\(self?.textview.text ?? "")"
                                }, loadStatus: { [weak self] (player, status) in
                                    if status == .readyToPlay {
                                        self?.totalTimeLabel.text = self?.timeStringFromSeconds(seconds: player.totalTime ?? 0)
                                        self?.textview.text = "加载状态：准备完毕，可以播放。\n\(self?.textview.text ?? "")"
                                    } else if status == .unknown {
                                        self?.textview.text = "加载状态：未知状态，此时不能播放。\n\(self?.textview.text ?? "")"
                                    } else if status == .failed {
                                        self?.textview.text = "加载状态：加载失败，网络或者服务器出现问题。\(String(describing: player.playerItem?.error))\n\(self?.textview.text ?? "")"
                                    }
                                }, bufferPercent: { [weak self] (player, bufferPercent) in
                                    self?.bufferLabel.text = "缓冲进度: \(String(format: "%.4f", Float(bufferPercent)))"
                                    self?.bufferView.progress = Float(bufferPercent)
                                }, willSeek: { (player, curtPos, toPos) in
                                    
                                }, seekComplete: { (player, prePos, curtPos) in

                                }, buffering: { [weak self] (player) in
                                    self?.textview.text = "可用缓冲耗尽，将停止播放！\n\(self?.textview.text ?? "")"
                                    player.pause()

                                }, bufferFinish: { [weak self] (player) in
                                    self?.textview.text = "可无延迟播放......\n\(self?.textview.text ?? "")"
                                    guard let `self` = self else {
                                        return
                                    }
                                    if !self.manualyPause {
                                        player.play()
                                    }

                                }, error: { [weak self] (player, error) in
                                    self?.textview.text = "播放出错: \(String(describing: error))\n\(self?.textview.text ?? "")"
                                })

        view.layer.addSublayer(zlAVPlayer.playerLayer!)
        zlAVPlayer.play()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        zlAVPlayer.playerLayer?.frame = CGRect(x: 0, y: view.bounds.maxY/3, width: view.bounds.width, height: view.bounds.height/2)
    }

    @IBAction func play(_ sender: Any) {
        manualyPause = false
        zlAVPlayer.play()
    }
    
    @IBAction func pause(_ sender: Any) {
        manualyPause = true
        zlAVPlayer.pause()
    }
    
    private func timeStringFromSeconds(seconds: Double) -> String {
        return String(format: "%ld:%.2ld", Int(seconds)/60, Int(seconds) % 60)
    }
    
}

