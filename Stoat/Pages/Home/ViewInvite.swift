//
//  ViewInvite.swift
//  Revolt
//
//  Created by Angelo on 12/09/2024.
//

import Foundation
import SwiftUI

struct ViewInvite: View {
    @EnvironmentObject var viewState: ViewState
    
    var code: String
    
    @State var info: InviteInfoResponse?? = nil
    
    var body: some View {
        ZStack {
            switch info {
                case .none:
                    LoadingSpinnerView(frameSize: CGSize(width: 32, height: 32), isActionComplete: .constant(false))
                case .some(.none):
                    Text("Invalid invite")
                case .group(let groupInfo):
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(viewState.theme.foreground2)

                        Text(verbatim: groupInfo.channel_name)
                            .font(.title2)
                            .fontWeight(.medium)

                        if let description = groupInfo.channel_description, !description.isEmpty {
                            Contents(text: .constant(description), fontSize: 15)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack {
                            Text("Invited by")

                            HStack {
                                if let avatar = groupInfo.user_avatar {
                                    LazyImage(source: .file(avatar), clipTo: Circle())
                                        .frame(width: 24, height: 24)
                                }

                                Text(verbatim: groupInfo.user_name)
                            }
                        }
                        .foregroundStyle(viewState.theme.foreground2)

                    }
                    .padding(16)
                    .background(viewState.theme.background.opacity(0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                case .server(let serverInfo):
                    if let banner = serverInfo.server_banner {
                        LazyImage(source: .file(banner), clipTo: Rectangle())
                    }
                    
                    VStack(spacing: 16) {
                        Group {
                            if let server_icon = serverInfo.server_icon {
                                LazyImage(source: .file(server_icon), clipTo: Circle())
                            } else {
                                FallbackServerIcon(name: serverInfo.server_name, clipTo: Circle())
                            }
                        }
                        .frame(width: 48, height: 48)
                        
                        HStack(alignment: .center, spacing: 8) {
                            ServerBadges(value: serverInfo.server_flags)
                            
                            Text(verbatim: serverInfo.server_name)
                                .fontWeight(.medium)
                        }
                        
                        HStack {
                            Text("#\(serverInfo.channel_name)")
                            
                            Circle()
                                .frame(width: 4, height: 4)
                            
                            Text("\(serverInfo.member_count) users")
                        }
                        .foregroundStyle(viewState.theme.foreground2)

                        HStack {
                            Text("Invited by")
                            
                            HStack {
                                if let avatar = serverInfo.user_avatar {
                                    LazyImage(source: .file(avatar), clipTo: Circle())
                                        .frame(width: 24, height: 24)
                                }
                                
                                Text(verbatim: serverInfo.user_name)
                            }
                        }
                        
                        Button {
                            Task {
                                let result = await viewState.http.joinServer(code: code)
                                switch result {
                                    case .success(let join):
                                        let member = try! await viewState.http.fetchMember(server: join.server.id, member: viewState.currentUser!.id).get()
                                        
                                        viewState.members[join.server.id] = [member.id.user: member]
                                        viewState.servers[join.server.id] = join.server
                                        
                                        for channel in join.channels {
                                            viewState.channels[channel.id] = channel
                                            viewState.channelMessages[channel.id] = []
                                        }
                                        viewState.selectChannel(inServer: serverInfo.server_id, withId: serverInfo.channel_id)
                                    case .failure(let e):
                                        if case .HTTPError(let body, _) = e, let body, body.type == "AlreadyInServer" {
                                            viewState.selectChannel(inServer: serverInfo.server_id, withId: serverInfo.channel_id)
                                            viewState.path.removeLast()
                                        }
                                }
                            }
                        } label: {
                            Text("Accept Invite")
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)
                        }
                        .background(viewState.theme.background2)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(16)
                    .background(viewState.theme.background.opacity(0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .toolbarBackground(viewState.theme.topBar, for: .automatic)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack {
                    Text("Join Invite")
                }
            }
        }
        .task {
            if let info = try? await viewState.http.fetchInvite(code: code).get() {
                self.info = info
            } else {
                self.info = .some(.none)
            }
        }
    }
}
