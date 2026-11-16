//
//  App.swift
//  程序入口。
//
//  2026-11-16 小鱼
//  这个文件漏了整整四轮构建。SwiftUI 必须有 @main 标记的 App 结构体，
//  否则链接阶段会报 "linker command failed with exit code 1" ——
//  因为找不到 main 这个符号。不是语法错，是根本没进入口。
//

import SwiftUI

@main
struct PhotoAssistantApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
