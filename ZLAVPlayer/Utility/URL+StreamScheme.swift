//
//  URL+StreamScheme.swift
//  ZLAVPlayer
//
//  Created by 赵磊 on 2018/6/29.
//  Copyright © 2018年 zl. All rights reserved.
//

import Foundation

extension URL {

    /// 视频代理的scheme
    var streamSchemeURL: URL {
        var component = URLComponents(url: self, resolvingAgainstBaseURL: true)!
        component.scheme = "Stream"
        return component.url!
    }
}
