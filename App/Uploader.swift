//
//  Uploader.swift
//  把扫到的照片传回看板。
//
//  2026-11-16 小鱼
//  契约（跟电脑端那套复用同一个服务，不多起东西）：
//    POST {base}/api/phone/report      JSON，报设备名、系统版本、照片总数、上次上传到哪
//    POST {base}/api/phone/photo       二进制，头里带 localId / 文件名 / 拍摄时间 / 大小
//
//  base 默认取 Tailscale 里看板主机的地址。手机装 Tailscale 登录同一个号就能直连，
//  不需要公网中转，也不需要域名。
//

import Foundation
import UIKit

final class Uploader {

    /// 看板服务地址。装 Tailscale 后能直接访问这个内网 IP。
    static var baseURL = "http://100.95.172.88:8765"

    /// 同一台手机重复上报时用这个 key 认人
    static var deviceKey: String {
        let model = UIDevice.current.model
        let name = UIDevice.current.name
        let id = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        return "\(name)|\(model)|\(id)"
    }

    // MARK: - 上报设备

    struct Report: Codable {
        var device: String
        var model: String
        var system: String
        var photoCount: Int
        var lastUploaded: String?      // 最后一次成功上传的 localId
        var clientVersion: String
    }

    static func report(photoCount: Int, lastUploaded: String?,
                       completion: @escaping (Bool, String) -> Void) {
        let body = Report(
            device: UIDevice.current.name,
            model: UIDevice.current.model,
            system: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            photoCount: photoCount,
            lastUploaded: lastUploaded,
            clientVersion: "0.1.0"
        )
        guard let url = URL(string: baseURL + "/api/phone/report") else {
            return completion(false, "地址不对")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = try? JSONEncoder().encode(body)

        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let err = err {
                    return completion(false, err.localizedDescription)
                }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                completion(code >= 200 && code < 300, "HTTP \(code)")
            }
        }.resume()
    }

    // MARK: - 上传单张照片

    /// 一次传一张，串行。失败返回 false，调用方决定要不要重试。
    static func upload(_ asset: ScannedAsset, completion: @escaping (Bool, String) -> Void) {
        guard let data = asset.data, data.count > 0 else {
            return completion(false, "没有数据")
        }
        guard let url = URL(string: baseURL + "/api/phone/photo") else {
            return completion(false, "地址不对")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        // 元数据放头里，避免 multipart 的复杂度；文件名用百分号编码防止中文头被拒
        req.setValue(asset.localId, forHTTPHeaderField: "X-Asset-Id")
        req.setValue(asset.filename.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "unknown",
                     forHTTPHeaderField: "X-Filename")
        req.setValue(asset.mediaType, forHTTPHeaderField: "X-Media-Type")
        req.setValue(String(asset.pixelWidth), forHTTPHeaderField: "X-Width")
        req.setValue(String(asset.pixelHeight), forHTTPHeaderField: "X-Height")
        if let d = asset.creationDate {
            req.setValue(String(d.timeIntervalSince1970), forHTTPHeaderField: "X-Created-At")
        }
        req.setValue(deviceKey, forHTTPHeaderField: "X-Device")
        req.timeoutInterval = 60
        req.httpBody = data

        URLSession.shared.dataTask(with: req) { _, resp, err in
            DispatchQueue.main.async {
                if let err = err {
                    return completion(false, err.localizedDescription)
                }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                completion(code >= 200 && code < 300, "HTTP \(code)")
            }
        }.resume()
    }

    // MARK: - 批量上传

    /// 串行传一批。每传成功一张就回报一次进度和它的 localId，方便断点续传。
    static func uploadAll(_ assets: [ScannedAsset],
                          progress: @escaping (Int, Int, String) -> Void,
                          completion: @escaping (Int, Int) -> Void) {
        var done = 0
        var failed = 0
        let total = assets.count

        func next(_ i: Int) {
            if i >= total {
                return completion(done, failed)
            }
            let a = assets[i]
            upload(a) { ok, _ in
                if ok {
                    done += 1
                    progress(done, total, a.localId)
                } else {
                    failed += 1
                    progress(done, total, "")
                }
                // 串行，给网络一点喘息
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.15) {
                    next(i + 1)
                }
            }
        }
        next(0)
    }
}
