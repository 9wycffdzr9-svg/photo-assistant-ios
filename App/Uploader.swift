//
//  Uploader.swift
//  把扫到的照片传回看板。
//
//  2026-11-16 小鱼（v2）
//  v1 的问题：ScannedAsset 里带着 Data，扫一批就意味着一批照片同时往内存里读，
//  手机上一堆 iCloud 照片直接卡死。现在数据是按需读的：传哪张读哪张。
//

import Foundation
import UIKit
import Photos

final class Uploader {

    /// 看板服务地址。
    /// 2026-11-16：原来写死 Tailscale 的 100.x 地址，手机没装 Tailscale 就永远连不上，
    /// 表现是进度条 0/N 一个错都不报。现在默认走局域网，存过就用存的。
    static let defaultServer = "http://192.168.0.56:8765"

    static var baseURL: String {
        get {
            let v = UserDefaults.standard.string(forKey: "xy.server") ?? ""
            return v.isEmpty ? defaultServer : v
        }
        set { UserDefaults.standard.set(newValue, forKey: "xy.server") }
    }

    /// 纯 ASCII 的机器 ID（中文名不能放 HTTP 头，会被中间层拆成下划线）
    static var deviceId: String {
        let k = "xy.device.id"
        if let v = UserDefaults.standard.string(forKey: k), !v.isEmpty { return v }
        // 取 UDID 派生的短串，稳定且不含中文
        let raw = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let clean = raw.replacingOccurrences(of: "-", with: "").prefix(12).uppercased()
        let v = "IP" + clean
        UserDefaults.standard.set(v, forKey: k)
        return v
    }

    /// 给人看的名字（走 JSON body，不走头）
    static var deviceLabel: String {
        "\(UIDevice.current.name)|\(UIDevice.current.model)"
    }

    // MARK: - 上报设备

    struct Report: Codable {
        var device: String
        var model: String
        var system: String
        var photoCount: Int
        var lastUploaded: String?
        var clientVersion: String
    }

    static func report(photoCount: Int, lastUploaded: String?,
                       completion: @escaping (Bool, String) -> Void) {
        let body = Report(
            device: deviceLabel,
            model: UIDevice.current.model,
            system: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            photoCount: photoCount,
            lastUploaded: lastUploaded,
            clientVersion: "0.2.0"
        )
        guard let url = URL(string: baseURL + "/api/phone/report") else {
            return completion(false, "地址不对")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = try? JSONEncoder().encode(body)

        URLSession.shared.dataTask(with: req) { _, resp, err in
            DispatchQueue.main.async {
                if let err = err { return completion(false, err.localizedDescription) }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                completion(code >= 200 && code < 300, "HTTP \(code)")
            }
        }.resume()
    }

    // MARK: - 传一张

    /// 传一张。内部会先把这张的数据读出来（可能在 iCloud 上，要等几秒）。
    static func uploadOne(_ item: ScannedAsset,
                          completion: @escaping (Bool, String) -> Void) {
        guard item.mediaType == "image" else {
            return completion(false, "跳过视频")
        }
        guard let asset = PhotoScanner.asset(withLocalId: item.localId) else {
            return completion(false, "找不到这张")
        }
        PhotoScanner.loadData(for: asset) { data in
            guard let data = data, data.count > 0 else {
                return completion(false, "读不到数据")
            }
            send(item: item, data: data, completion: completion)
        }
    }

    private static func send(item: ScannedAsset, data: Data,
                             completion: @escaping (Bool, String) -> Void) {
        guard let url = URL(string: baseURL + "/api/phone/photo") else {
            return completion(false, "地址不对")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        // 头里只放 ASCII；文件名做百分号编码
        req.setValue(deviceId, forHTTPHeaderField: "X-Device")
        req.setValue(percentEncoded(deviceLabel), forHTTPHeaderField: "X-Device-Label")
        req.setValue(item.localId, forHTTPHeaderField: "X-Asset-Id")
        req.setValue(percentEncoded(item.filename), forHTTPHeaderField: "X-Filename")
        req.setValue(item.mediaType, forHTTPHeaderField: "X-Media-Type")
        req.setValue(String(item.pixelWidth), forHTTPHeaderField: "X-Width")
        req.setValue(String(item.pixelHeight), forHTTPHeaderField: "X-Height")
        if let d = item.creationDate {
            req.setValue(String(d.timeIntervalSince1970), forHTTPHeaderField: "X-Created-At")
        }
        req.timeoutInterval = 120
        req.httpBody = data

        URLSession.shared.dataTask(with: req) { _, resp, err in
            DispatchQueue.main.async {
                if let err = err { return completion(false, err.localizedDescription) }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                completion(code >= 200 && code < 300, "HTTP \(code)")
            }
        }.resume()
    }

    private static func percentEncoded(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? "unknown"
    }

    // MARK: - 批量（串行，一次只读一张）

    static func uploadAll(_ items: [ScannedAsset],
                          progress: @escaping (Int, Int, String) -> Void,
                          completion: @escaping (Int, Int) -> Void) {
        var done = 0
        var failed = 0
        let total = items.count

        func next(_ i: Int) {
            if i >= total { return completion(done, failed) }
            let a = items[i]
            uploadOne(a) { ok, _ in
                if ok { done += 1 } else { failed += 1 }
                progress(done, total, a.filename)
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.05) {
                    next(i + 1)
                }
            }
        }
        next(0)
    }
}
