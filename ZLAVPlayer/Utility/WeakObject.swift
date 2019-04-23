//
//  WeakObject.swift
//  ZLAVPlayer
//
//  Created by 赵磊 on 2018/9/21.
//  Copyright © 2018年 zl. All rights reserved.
//

import Foundation

/**
    弱引用对象容器
 */
class WeakObject<T: AnyObject> where T: Equatable {

    weak var target: T?

    init(target: T) {
        self.target = target
    }
}
