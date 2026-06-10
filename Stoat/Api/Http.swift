//
//  Http.swift
//  Revolt
//
//  Created by Zomatree on 21/04/2023.
//

import Foundation
import Alamofire
import CryptoKit
import Types
import os

enum RevoltError: Error {
    struct RevoltHTTPError: Codable {
        var type: String
        var location: String
    }
    case Alamofire(AFError)
    case HTTPError(RevoltHTTPError?, Int)
    case JSONDecoding(any Error)
}

private let defaultUploadChunkSize = 50 * 1024 * 1024

private struct ChunkUploadResponse: Decodable {
    var upload_id: String
    var chunk_index: Int
    var received_chunks: Int
    var total_chunks: Int
}

private struct CompleteUploadPayload: Encodable {
    var filename: String
    var total_chunks: Int
    var total_size: Int
    var sha256: String
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}

struct HTTPClient {
    var token: String?
    var baseURL: String
    var apiInfo: ApiInfo?
    var session: Alamofire.Session
    var logger: Logger

    init(token: String?, baseURL: String) {
        self.token = token
        self.baseURL = baseURL
        self.apiInfo = nil
        self.session = Alamofire.Session()
        self.logger = Logger(subsystem: "chat.stoat.app", category: "http")
    }

    func innerReq<
        I: Encodable
    >(
        method: HTTPMethod,
        route: String,
        parameters: I? = nil as Int?,
        encoder: ParameterEncoder = JSONParameterEncoder.default,
        headers hdrs: HTTPHeaders? = nil
    ) async -> Result<DataResponse<String, AFError>, RevoltError> {
        var headers: HTTPHeaders = hdrs ?? HTTPHeaders()

        if token != nil {
            headers.add(name: "x-session-token", value: token!)
        }

        let req = self.session.request(
            "\(baseURL)\(route)",
            method: method,
            parameters: parameters,
            encoder: encoder,
            headers: headers
        )
        
        let response = await req.serializingString()
            .response

        let code = response.response?.statusCode ?? 500

        do {
            let resp = try response.result.get()
            logger.debug("OK:    Received response \(code) for route \(method.rawValue) \(baseURL)\(route) with result \(resp)")
        } catch {
            logger.debug("Error: Received response \(code) for route \(method.rawValue) \(baseURL)\(route) with result \(response.error)")
        }

        if ![200, 201, 202, 203, 204, 205, 206, 207, 208, 226].contains(code) {
            let errorBody = try? response.value.map { try JSONDecoder().decode(RevoltError.RevoltHTTPError.self, from: $0.data(using: .utf8)!) }
            return .failure(.HTTPError(errorBody, code))
        }

        return .success(response)

    }

    func req<
        I: Encodable,
        O: Decodable
    >(
        method: HTTPMethod,
        route: String,
        parameters: I? = nil as Int?,
        encoder: ParameterEncoder = JSONParameterEncoder.default,
        headers: HTTPHeaders? = nil
    ) async -> Result<O, RevoltError> {
        return await innerReq(method: method, route: route, parameters: parameters, encoder: encoder, headers: headers).flatMap { response in
            if let error = response.error {
                return .failure(.Alamofire(error))
            } else if let data = response.data {
                do {
                    return .success(try JSONDecoder().decode(O.self, from: data))
                } catch {
                    return .failure(.JSONDecoding(error))
                }

            } else {
                return .failure(.HTTPError(nil, 0))
            }
        }
    }

    func req<
        I: Encodable
    >(
        method: HTTPMethod,
        route: String,
        parameters: I? = nil as Int?,
        encoder: ParameterEncoder = JSONParameterEncoder.default,
        headers: HTTPHeaders? = nil
    ) async -> Result<EmptyResponse, RevoltError> {
        return await innerReq(method: method, route: route, parameters: parameters, encoder: encoder, headers: headers).flatMap { response in
            if let error = response.error {
                return .failure(.Alamofire(error))
            } else {
                return .success(EmptyResponse())
            }
        }
    }

    func fetchSelf() async -> Result<User, RevoltError> {
        await req(method: .get, route: "/users/@me")
    }
    
    func signout() async -> Result<EmptyResponse, RevoltError> {
        await req(method: .post, route: "/auth/session/logout")
    }

    func fetchApiInfo() async -> Result<ApiInfo, RevoltError> {
        await req(method: .get, route: "/")
    }

    func sendMessage(channel: String, replies: [ApiReply], content: String, attachments: [(Data, String)], nonce: String) async -> Result<Message, RevoltError> {
        var attachmentIds: [String] = []

        for attachment in attachments {
            let response = try! await uploadFile(data: attachment.0, name: attachment.1, category: .attachment).get()

            attachmentIds.append(response.id)
        }

        return await req(method: .post, route: "/channels/\(channel)/messages", parameters: SendMessage(replies: replies, content: content, attachments: attachmentIds))
    }

    func fetchUser(user: String) async -> Result<User, RevoltError> {
        await req(method: .get, route: "/users/\(user)")
    }

    func deleteMessage(channel: String, message: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .delete, route: "\(baseURL)/channels/\(channel)/messages/\(message)")
    }

    func fetchHistory(channel: String, limit: Int, before: String?) async -> Result<FetchHistory, RevoltError> {
        var url = "/channels/\(channel)/messages?limit=\(limit)&include_users=true"

        if let before = before {
            url = "\(url)&before=\(before)"
        }

        return await req(method: .get, route: url)
    }

    func fetchMessage(channel: String, message: String) async -> Result<Message, RevoltError> {
        await req(method: .get, route: "/channels/\(channel)/messages/\(message)")
    }

    func fetchDms() async -> Result<[Channel], RevoltError> {
        await req(method: .get, route: "/users/dms")
    }

    func fetchProfile(user: String) async -> Result<Profile, RevoltError> {
        await req(method: .get, route: "/users/\(user)/profile")
    }

    func uploadFile(data: Data, name: String, category: FileCategory) async -> Result<AutumnResponse, RevoltError> {
        let url = "\(apiInfo!.features.autumn.url)/\(category.rawValue)"
        let uploadId = UUID().uuidString.lowercased()
        let configuredChunkSize = apiInfo?.features.limits?.global?.chunk_upload_size ?? defaultUploadChunkSize
        let chunkSize = configuredChunkSize > 0 ? configuredChunkSize : defaultUploadChunkSize
        let totalChunks = max(1, Int(ceil(Double(data.count) / Double(chunkSize))))
        let checksum = sha256Hex(data)

        var headers: HTTPHeaders = HTTPHeaders()

        if token != nil {
            headers.add(name: "x-session-token", value: token!)
        }

        for chunkIndex in 0..<totalChunks {
            let start = chunkIndex * chunkSize
            let end = min(data.count, start + chunkSize)
            let chunk = data.subdata(in: start..<end)

            let chunkResult = await session.upload(
                multipartFormData: { form in
                    form.append(uploadId.data(using: .utf8)!, withName: "upload_id")
                    form.append(String(chunkIndex).data(using: .utf8)!, withName: "chunk_index")
                    form.append(String(totalChunks).data(using: .utf8)!, withName: "total_chunks")
                    form.append(String(data.count).data(using: .utf8)!, withName: "total_size")
                    form.append(chunk, withName: "chunk", fileName: name)
                },
                to: "\(url)/chunks",
                headers: headers
            )
                .validate()
                .serializingDecodable(ChunkUploadResponse.self, decoder: JSONDecoder())
                .response
                .result

            if case .failure(let error) = chunkResult {
                return .failure(.Alamofire(error))
            }
        }

        return await session.request(
            "\(url)/chunks/\(uploadId)/complete",
            method: .post,
            parameters: CompleteUploadPayload(
                filename: name,
                total_chunks: totalChunks,
                total_size: data.count,
                sha256: checksum
            ),
            encoder: JSONParameterEncoder.default,
            headers: headers
        )
            .validate()
            .serializingDecodable(decoder: JSONDecoder())
            .response
            .result
            .mapError(RevoltError.Alamofire)
    }

    func fetchSessions() async -> Result<[Types.Session], RevoltError> {
        await req(method: .get, route: "/auth/session/all")
    }

    func deleteSession(session: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .delete, route: "/auth/session/\(session)")
    }

    func joinServer(code: String) async -> Result<JoinResponse, RevoltError> {
        await req(method: .post, route: "/invites/\(code)")
    }

    func reportMessage(id: String, reason: ContentReportPayload.ContentReportReason, userContext: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .post, route: "/safety/report", parameters: ContentReportPayload(type: .Message, contentId: id, reason: reason, userContext: userContext))
    }

    func createAccount(email: String, password: String, invite: String?, captcha: String?) async -> Result<EmptyResponse, RevoltError> {
        return await req(method: .post, route: "/auth/account/create", parameters: AccountCreatePayload(email: email, password: password, invite: invite, captcha: captcha))
    }

    func createAccount_VerificationCode(code: String) async -> Result<AccountCreateVerifyResponse, RevoltError> {
        await req(method: .post, route: "/auth/account/verify/\(code)")
    }

    func createAccount_ResendVerification(email: String, captcha: String?) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .post, route: "/auth/account/reverify", parameters: ["email": email, "captcha": captcha])
    }

    func sendResetPasswordEmail(email: String, captcha: String?) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .post, route: "/auth/account/reverify", parameters: ["email": email, "captcha": captcha])
    }

    func resetPassword(token: String, password: String, removeSessions: Bool = false) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .patch, route: "/auth/account/reset_password", parameters: PasswordResetPayload(token: token, password: password))
    }

    func checkOnboarding() async -> Result<OnboardingStatusResponse, RevoltError> {
        await req(method: .get, route: "/onboard/hello")
    }

    func completeOnboarding(username: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .post, route: "/onboard/complete", parameters: ["username": username])
    }

    func acceptFriendRequest(user: String) async -> Result<User, RevoltError> {
        await req(method: .put, route: "/users/\(user)/friend")
    }

    func removeFriend(user: String) async -> Result<User, RevoltError> {
        await req(method: .delete, route: "/users/\(user)/friend")
    }

    func blockUser(user: String) async -> Result<User, RevoltError> {
        await req(method: .put, route: "/users/\(user)/block")
    }

    func unblockUser(user: String) async -> Result<User, RevoltError> {
        await req(method: .delete, route: "/users/\(user)/block")
    }

    func sendFriendRequest(username: String) async -> Result<User, RevoltError> {
        await req(method: .post, route: "/users/friend", parameters: ["username": username])
    }

    func openDm(user: String) async -> Result<Channel, RevoltError> {
        await req(method: .get, route: "/users/\(user)/dm")
    }

    func fetchUnreads() async -> Result<[Unread], RevoltError> {
        await req(method: .get, route: "/sync/unreads")
    }

    func ackMessage(channel: String, message: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .put, route: "/channels/\(channel)/ack/\(message)")
    }

    func createGroup(name: String, users: [String]) async -> Result<Channel, RevoltError> {
        await req(method: .post, route: "/channels/create", parameters: GroupChannelCreate(name: name, users: users))
    }

    func createInvite(channel: String) async -> Result<Invite, RevoltError> {
        await req(method: .post, route: "/channels/\(channel)/invites")
    }
    
    func joinVoiceChannel(channel: String, node: String) async -> Result<VoiceChannelToken, RevoltError> {
        await req(method: .post, route: "/channels/\(channel)/join_call", parameters: ["node": node])
    }

    func fetchMember(server: String, member: String) async -> Result<Member, RevoltError> {
        await req(method: .get, route: "/servers/\(server)/members/\(member)")
    }

    func editServer(server: String, edits: ServerEdit) async -> Result<Server, RevoltError> {
        await req(method: .patch, route: "/servers/\(server)", parameters: edits)
    }

    func reactMessage(channel: String, message: String, emoji: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .put, route: "/channels/\(channel)/messages/\(message)/reactions/\(emoji)")
    }
    
    func unreactMessage(channel: String, message: String, emoji: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .delete, route: "/channels/\(channel)/messages/\(message)/reactions/\(emoji)")
    }
    
    // settings stuff
    func fetchAccount() async -> Result<AuthAccount, RevoltError> {
        await req(method: .get, route: "/auth/account")
    }

    func fetchMFAStatus() async -> Result<AccountSettingsMFAStatus, RevoltError> {
        await req(method: .get, route: "/auth/mfa")
    }

    func submitMFATicket(password: String) async -> Result<MFATicketResponse, RevoltError> {
        await req(method: .put, route: "/auth/mfa/ticket", parameters: ["password": password])
    }

    func submitMFATicket(totp: String) async -> Result<MFATicketResponse, RevoltError> {
        await req(method: .put, route: "/auth/mfa/ticket", parameters: ["totp_code": totp])
    }

    func submitMFATicket(recoveryCode: String) async -> Result<MFATicketResponse, RevoltError> {
        await req(method: .put, route: "/auth/mfa/ticket", parameters: ["recovery_code": recoveryCode])
    }
    
    func generateRecoveryCodes(mfaToken: String) async -> Result<[String], RevoltError> {
        let headers = HTTPHeaders(dictionaryLiteral: ("X-Mfa-Ticket", mfaToken))
        return await req(method: .patch, route: "/auth/mfa/recovery", headers: headers)
    }
    
    func getTOTPSecret(mfaToken: String) async -> Result<TOTPSecretResponse, RevoltError> {
        let headers = HTTPHeaders(dictionaryLiteral: ("X-Mfa-Ticket", mfaToken))
        return await req(method: .post, route: "/auth/mfa/totp", headers: headers)
    }

    /// This should be called only after fetching the secret AND verifying the user has the authenticator set up correctly
    func enableTOTP(mfaToken: String, totp_code: String) async -> Result<EmptyResponse, RevoltError> {
        let headers = HTTPHeaders(dictionaryLiteral: ("X-Mfa-Ticket", mfaToken))
        return await req(method: .put, route: "/auth/mfa/totp", parameters: ["totp_code": totp_code], headers: headers)
    }

    func disableTOTP(mfaToken: String) async -> Result<EmptyResponse, RevoltError> {
        let headers = HTTPHeaders(dictionaryLiteral: ("X-Mfa-Ticket", mfaToken))
        return await req(method: .delete, route: "/auth/mfa/totp", headers: headers)
    }

    func updateUsername(newName: String, password: String) async -> Result<User, RevoltError> {
        await req(method: .patch, route: "/users/@me/username", parameters: ["username": newName, "password": password])
    }
    
    func updatePassword(newPassword: String, oldPassword: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .patch, route: "/auth/account/change/password", parameters: ["password": newPassword, "current_password": oldPassword])
    }
    
    func disableAccount(mfaToken: String) async -> Result<EmptyResponse, RevoltError> {
        let headers = HTTPHeaders(dictionaryLiteral: ("X-Mfa-Ticket", mfaToken))
        return await req(method: .post, route: "/auth/account/disable", headers: headers)
    }
    
    func deleteAccount(mfaToken: String) async -> Result<EmptyResponse, RevoltError> {
        let headers = HTTPHeaders(dictionaryLiteral: ("X-Mfa-Ticket", mfaToken))
        return await req(method: .post, route: "/auth/account/delete", headers: headers)
    }
    
    func editMessage(channel: String, message: String, edits: MessageEdit) async -> Result<Message, RevoltError> {
        await req(method: .patch, route: "/channels/\(channel)/messages/\(message)", parameters: edits)
    }
    
    func uploadNotificationToken(token: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .post, route: "/push/subscribe", parameters: ["endpoint": "apn", "p256dh": "", "auth": token])
    }
    
    func revokeNotificationToken() async -> Result<EmptyResponse, RevoltError> {
        await req(method: .post, route: "/push/unsubscribe")
    }
    
    func searchChannel(channel: String, query: String) async -> Result<SearchResponse, RevoltError> {
        await req(method: .post, route: "/channels/\(channel)/search", parameters: ChannelSearchPayload(query: query, sort: .latest, include_users: true))
    }
    
    func fetchMutuals(user: String) async -> Result<MutualsResponse, RevoltError> {
        await req(method: .get, route: "/users/\(user)/mutual")
    }
    
    func fetchInvite(code: String) async -> Result<InviteInfoResponse, RevoltError> {
        await req(method: .get, route: "/invites/\(code)")
    }
    
    func editRole(server: String, role: String, payload: RoleEditPayload) async -> Result<Role, RevoltError> {
        await req(method: .patch, route: "/servers/\(server)/roles/\(role)", parameters: payload)
    }
    
    func setRolePermissions(server: String, role: String, overwrite: Overwrite) async -> Result<Server, RevoltError> {
        await req(method: .put, route: "/servers/\(server)/permissions/\(role)", parameters: ["permissions": ["allow": overwrite.a, "deny": overwrite.d]])
    }
    
    func deleteRole(server: String, role: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .delete, route: "/server/\(server)/roles/\(role)")
    }
    
    func createRole(server: String, name: String) async -> Result<RoleWithId, RevoltError> {
        await req(method: .post, route: "/servers/\(server)/roles", parameters: ["name": name])
    }
    
    func setDefaultRolePermissions(server: String, permissions: Permissions) async -> Result<Server, RevoltError> {
        await req(method: .put, route: "/servers/\(server)/permissions/default", parameters: ["permissions": permissions])
    }
    
    func setDefaultRoleChannelPermissions(channel: String, permissions: Permissions) async -> Result<Channel, RevoltError> {
        await req(method: .put, route: "/channels/\(channel)/permissions/default", parameters: ["permissions": permissions])
    }
    
    func setDefaultRoleChannelPermissions(channel: String, overwrite: Overwrite) async -> Result<Channel, RevoltError> {
        await req(method: .put, route: "/channels/\(channel)/permissions/default", parameters: ["permissions": ["allow": overwrite.a, "deny": overwrite.d]])
    }
    
    func setRoleChannelPermissions(channel: String, role: String, overwrite: Overwrite) async -> Result<Channel, RevoltError> {
        await req(method: .put, route: "/channels/\(channel)/permissions/\(role)", parameters: ["permissions": ["allow": overwrite.a, "deny": overwrite.d]])
    }
    
    func uploadEmoji(id: String, name: String, parent: EmojiParent, nsfw: Bool) async -> Result<Emoji, RevoltError> {
        await req(method: .put, route: "/custom/emoji/\(id)", parameters: CreateEmojiPayload(id: id, name: name, parent: parent, nsfw: nsfw))
    }

    func deleteEmoji(emoji: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .delete, route: "/custom/emoji/\(emoji)")
    }
    
    func fetchSettings(keys: [String]) async -> Result<SettingsResponse, RevoltError> {
        await req(method: .post, route: "/sync/settings/fetch", parameters: ["keys": keys])
    }
    
    func setSettings(key: String, value: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .post, route: "/sync/settings/set", parameters: [key: value.replacing("\"", with: "\\\"")])
    }
    
    func fetchChannelPins(channel: String) async -> Result<SearchResponse, RevoltError> {
        await req(method: .post, route: "/channels/\(channel)/search", parameters: ChannelSearchPayload(pinned: true, sort: .latest, include_users: true))
    }
    
    func pinMessage(channel: String, message: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .post, route: "/channels/\(channel)/messages/\(message)/pin")
    }
    
    func unpinMessage(channel: String, message: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .delete, route: "/channels/\(channel)/messages/\(message)/pin")
    }
    
    func fetchBots() async -> Result<BotsResponse, RevoltError> {
        await req(method: .get, route: "/bots/@me")
    }
    
    func createBot(username: String) async -> Result<Bot, RevoltError> {
        await req(method: .post, route: "/bots/create", parameters: ["name": username])
    }
    
    func deleteBot(id: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .delete, route: "/bots/\(id)")
    }
    
    func editBot(id: String, parameters: EditBotPayload) async -> Result<Bot, RevoltError> {
        await req(method: .patch, route: "/bots/\(id)", parameters: parameters)
    }
    
    func fetchMembers(server: String, excludeOffline: Bool) async -> Result<MembersWithUsers, RevoltError> {
        await req(method: .get, route: "/servers/\(server)/members?exclude_offline=\(excludeOffline ? "true" : "false")")
    }
    
    func fetchInvites(server: String) async -> Result<[Invite], RevoltError> {
        await req(method: .get, route: "/servers/\(server)/invites")
    }
    
    func fetchBans(server: String) async -> Result<BansResponse, RevoltError> {
        await req(method: .get, route: "/servers/\(server)/bans")
    }

    func editMember(server: String, user: String, payload: EditMemberPayload) async -> Result<Member, RevoltError> {
        await req(method: .patch, route: "/servers/\(server)/members/\(user)", parameters: payload)
    }
    
    func unbanUser(server: String, user: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .delete, route: "/servers/\(server)/bans/\(user)")
    }
    
    func createWebhook(channel: String, body: CreateWebhookPayload) async -> Result<Webhook, RevoltError> {
        await req(method: .post, route: "/channels/\(channel)/webhooks", parameters: body)
    }
    
    func fetchWebhooks(channel: String) async -> Result<[Webhook], RevoltError> {
        await req(method: .get, route: "/channels/\(channel)/webhooks")
    }
    
    func deleteWebhook(webhook: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .delete, route: "/webhooks/\(webhook)")
    }
}
