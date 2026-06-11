//
//  ServerInvitesSettings.swift
//  Stoat
//

import SwiftUI
import Types

struct ServerInvitesSettings: View {
    @EnvironmentObject var viewState: ViewState

    @Binding var server: Server

    @State var invites: [Invite]?
    @State var creators: [String: User] = [:]
    @State var selectedChannelId: String?
    @State var error: String?
    @State var isCreating = false

    var inviteChannels: [Channel] {
        server.channels
            .compactMap { viewState.channels[$0] }
            .filter {
                if case .text_channel = $0 { return true }
                return false
            }
    }

    func creatorId(for invite: Invite) -> String {
        switch invite {
            case .server(let invite):
                return invite.creator
            case .group(let invite):
                return invite.creator
        }
    }

    func channelId(for invite: Invite) -> String {
        switch invite {
            case .server(let invite):
                return invite.channel
            case .group(let invite):
                return invite.channel
        }
    }

    func fetchInviteCreators(_ invites: [Invite]) async {
        for invite in invites {
            let creatorId = creatorId(for: invite)

            if let user = viewState.users[creatorId] {
                creators[creatorId] = user
            } else if let user = try? await viewState.http.fetchUser(user: creatorId).get() {
                creators[creatorId] = user
                viewState.users[user.id] = user
            }
        }
    }

    func fetchInvites() async {
        do {
            let response = try await viewState.http.fetchInvites(server: server.id).get()
            invites = response
            error = nil
            await fetchInviteCreators(response)
        } catch let e {
            error = e.localizedDescription
        }
    }

    func createInvite() async {
        guard let channelId = selectedChannelId ?? inviteChannels.first?.id else { return }

        isCreating = true
        defer { isCreating = false }

        do {
            let invite = try await viewState.http.createInvite(channel: channelId).get()
            invites = [invite] + (invites ?? [])

            if let currentUser = viewState.currentUser {
                creators[currentUser.id] = currentUser
            }

            error = nil
        } catch let e {
            error = e.localizedDescription
        }
    }

    func deleteInvite(_ invite: Invite) async {
        do {
            let _ = try await viewState.http.deleteInvite(code: invite.id).get()
            invites?.removeAll { $0.id == invite.id }
            error = nil
        } catch let e {
            error = e.localizedDescription
        }
    }

    var body: some View {
        Group {
            if let error {
                Text(verbatim: error)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let invites {
                List {
                    Section("Create Invite") {
                        if inviteChannels.isEmpty {
                            Text("Create a text channel before inviting others.")
                                .foregroundStyle(viewState.theme.foreground2)
                        } else {
                            Picker("Channel", selection: Binding(
                                get: { selectedChannelId ?? inviteChannels.first?.id },
                                set: { selectedChannelId = $0 }
                            )) {
                                ForEach(inviteChannels, id: \.id) { channel in
                                    ChannelIcon(channel: channel)
                                        .tag(Optional(channel.id))
                                }
                            }

                            Button {
                                Task { await createInvite() }
                            } label: {
                                if isCreating {
                                    ProgressView()
                                } else {
                                    Text("Create invite")
                                }
                            }
                            .disabled(isCreating)
                        }
                    }
                    .listRowBackground(viewState.theme.background2)

                    Section("Invites - \(invites.count)") {
                        ForEach(invites) { invite in
                            HStack(spacing: 12) {
                                if let creator = creators[creatorId(for: invite)] {
                                    Avatar(user: creator)
                                        .frame(width: 32, height: 32)
                                } else {
                                    Circle()
                                        .fill(viewState.theme.background3)
                                        .frame(width: 32, height: 32)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: invite.id)
                                        .font(.headline)

                                    HStack(spacing: 4) {
                                        if let creator = creators[creatorId(for: invite)] {
                                            Text(verbatim: creator.display_name ?? creator.username)
                                        } else {
                                            Text("Unknown User")
                                        }

                                        if let channel = viewState.channels[channelId(for: invite)] {
                                            Text("•")
                                            ChannelIcon(channel: channel, spacing: 4, initialSize: (12, 12), frameSize: (16, 16))
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(viewState.theme.foreground2)
                                }

                                Spacer()

                                Button {
                                    copyText(text: invite.id)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task { await deleteInvite(invite) }
                                } label: {
                                    Label("Delete", systemImage: "trash.fill")
                                }
                            }
                        }
                    }
                    .listRowBackground(viewState.theme.background2)
                }
                .scrollContentBackground(.hidden)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .background(viewState.theme.background)
        .navigationTitle("Invites")
        .toolbarBackground(viewState.theme.topBar.color, for: .automatic)
        .task {
            selectedChannelId = selectedChannelId ?? inviteChannels.first?.id
            await fetchInvites()
        }
        .refreshable {
            await fetchInvites()
        }
    }
}

