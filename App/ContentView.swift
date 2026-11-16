//
//  ContentView.swift
//  主界面 + 权限闸门。
//
//  2026-11-16 小鱼（v2）
//  v1 卡死的原因：扫相册时就批量读图，iCloud 上的照片一张张拉，进度条不动。
//  现在扫描只取列表（秒级），读图放到上传阶段逐张做，进度条会实时往前走。
//

import SwiftUI
import UIKit

struct ContentView: View {

    @State private var granted = false
    @State private var limited = false
    @State private var photoCount = 0
    @State private var busy = false
    @State private var stage = ""          // 当前阶段文字
    @State private var doneCount = 0
    @State private var totalCount = 0
    @State private var failedCount = 0
    @State private var currentName = ""

    var body: some View {
        Group {
            if granted { mainView } else { gateView }
        }
        .onAppear { checkPermission() }
    }

    // MARK: - 权限闸门

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

                    VStack(alignment: .leading, spacing: 6) {
                        Text("相册里").font(.system(size: 13)).foregroundColor(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(photoCount)")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(Color(red: 0.05, green: 0.58, blue: 0.53))
                            Text("张照片和视频")
                                .font(.system(size: 14)).foregroundColor(.secondary)
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

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(headline).font(.system(size: 15, weight: .semibold))
                            Spacer()
                            if totalCount > 0 {
                                Text("\(doneCount)/\(totalCount)")
                                    .font(.system(size: 13)).foregroundColor(.secondary)
                            }
                        }

                        if totalCount > 0 {
                            ProgressView(value: Double(doneCount), total: Double(max(totalCount, 1)))
                                .tint(Color(red: 0.05, green: 0.58, blue: 0.53))
                        } else if busy {
                            // 扫描阶段没有分母，用不确定进度条，至少让人看到它在动
                            ProgressView()
                                .progressViewStyle(.linear)
                                .tint(Color(red: 0.05, green: 0.58, blue: 0.53))
                        }

                        if !stage.isEmpty {
                            Text(stage)
                                .font(.system(size: 12)).foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        if !currentName.isEmpty {
                            Text(currentName)
                                .font(.system(size: 11)).foregroundColor(.secondary.opacity(0.8))
                                .lineLimit(1)
                        }

                        HStack(spacing: 6) {
                            Text("服务器").font(.system(size: 11)).foregroundColor(.secondary)
                            Text(Uploader.baseURL).font(.system(size: 11)).foregroundColor(.secondary.opacity(0.8))
                            Spacer()
                        }

                        Button(action: { startSync() }) {
                            Text(busy ? "同步中，别退出" : "立即整理并同步")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(busy ? Color.gray.opacity(0.5)
                                                 : Color(red: 0.05, green: 0.58, blue: 0.53))
                                .cornerRadius(12)
                        }
                        .disabled(busy)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("相册助手")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var headline: String {
        if busy { return "正在同步…" }
        if doneCount > 0 { return "已同步 \(doneCount) 张" + (failedCount > 0 ? "（\(failedCount) 张失败）" : "") }
        return "还没同步过"
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
            granted = ok; limited = lim
            if ok { photoCount = PhotoScanner.count() }
        }
    }

    private func startSync() {
        guard !busy else { return }
        busy = true
        doneCount = 0
        totalCount = 0
        failedCount = 0
        currentName = ""
        stage = "正在列出相册…"

        // 第一步：只列清单，很快
        PhotoScanner.scan(since: nil, limit: 0, progress: { got, total in
            stage = "正在列出相册 \(got)/\(total)"
        }, completion: { items in
            totalCount = items.count
            doneCount = 0
            stage = "共 \(items.count) 张，正在上报设备"

            Uploader.report(photoCount: photoCount, lastUploaded: nil) { _, msg in
                stage = "设备已上报（\(msg)），开始传"

                Uploader.uploadAll(items, progress: { done, total, name in
                    doneCount = done
                    currentName = "刚传：\(name)"
                    stage = "已传 \(done)/\(total)"
                }, completion: { done, failed in
                    busy = false
                    doneCount = done
                    failedCount = failed
                    currentName = ""
                    stage = "同步结束：成功 \(done) 张，失败 \(failed) 张"
                })
            }
        })
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
