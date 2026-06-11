//
//  ServerSettings.swift
//  Revolt
//
//  Created by Angelo on 08/11/2023.
//

import Foundation
import SwiftUI
import Types

struct ServerSettings: View {
    @EnvironmentObject var viewState: ViewState
    @Environment(\.dismiss) var dismiss

    @Binding var server: Server
    
    @State var userPermissions: Permissions = Permissions.all
    @State var showDeleteServerDialog = false
    @State var isDeletingServer = false
    @State var deletionError: String?

    func deleteServer() async {
        guard !isDeletingServer else { return }

        isDeletingServer = true
        deletionError = nil
        defer { isDeletingServer = false }

        do {
            let _ = try await viewState.http.deleteServer(server: server.id).get()
            viewState.removeServerFromState(id: server.id)
            dismiss()
        } catch let e {
            deletionError = e.localizedDescription
        }
    }
    
    var body: some View {
        List {
            Section("Settings") {
                if userPermissions.contains(.manageServer) {
                    NavigationLink {
                        ServerOverviewSettings(server: $server)
                    } label: {
                        Image(systemName: "info.circle.fill")
                        Text("Overview")
                    }
                }
                
                if userPermissions.contains(.manageChannel) {
                    NavigationLink {
                        ServerCategoriesSettings(server: $server)
                    } label: {
                        Image(systemName: "list.bullet")
                        Text("Categories")
                    }
                }

                if userPermissions.contains(.manageRole) {
                    NavigationLink {
                        ServerRolesSettings(server: $server)
                    } label: {
                        Image(systemName: "flag.fill")
                        Text("Roles")
                    }
                }
            }
            .listRowBackground(viewState.theme.background2)
            
            Section("Customisation") {
                if userPermissions.contains(.manageCustomisation) {
                    NavigationLink {
                        ServerEmojiSettings(server: $server)
                    } label: {
                        Image(systemName: "face.smiling")
                        Text("Emojis")
                    }
                }
            }
            .listRowBackground(viewState.theme.background2)
            
            Section("User Management") {
                NavigationLink {
                    ServerMembersSettings(server: $server)
                } label: {
                    Image(systemName: "person.2.fill")
                    Text("Members")
                }
                
                if userPermissions.contains(.manageServer) {
                    NavigationLink {
                        ServerInvitesSettings(server: $server)
                    } label: {
                        Image(systemName: "envelope.fill")
                        Text("Invites")
                    }
                }
                
                if userPermissions.contains(.banMembers) {
                    NavigationLink {
                        ServerBanSettings(server: $server)
                    } label: {
                        Image(systemName: "person.fill.xmark")
                        Text("Bans")
                    }
                }
            }
            .listRowBackground(viewState.theme.background2)
            
            if server.owner == viewState.currentUser?.id {
                Button {
                    showDeleteServerDialog = true
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text(isDeletingServer ? "Deleting server..." : "Delete server")
                    }
                    .foregroundStyle(.red)
                }
                .disabled(isDeletingServer)
                .listRowBackground(viewState.theme.background2)
            }

            if let deletionError {
                Text(verbatim: deletionError)
                    .foregroundStyle(viewState.theme.error)
                    .listRowBackground(viewState.theme.background2)
            }

            
        }
        .scrollContentBackground(.hidden)
        .background(viewState.theme.background)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack {
                    ServerIcon(server: server, height: 24, width: 24, clipTo: Circle())
                    Text(verbatim: server.name)
                }
            }
        }
        .toolbarBackground(viewState.theme.topBar.color, for: .automatic)
        .confirmationDialog("Delete server?", isPresented: $showDeleteServerDialog) {
            Button("Delete server", role: .destructive) {
                Task { await deleteServer() }
            }
            .disabled(isDeletingServer)

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete \(server.name).")
        }
        .task {
            if let user = viewState.currentUser, let member = viewState.members[server.id]?[user.id] {
                userPermissions = resolveServerPermissions(user: user, member: member, server: server)
            }
        }
    }
}


#Preview {
    let viewState = ViewState.preview()

    return NavigationStack {
        ServerSettings(server: .constant(viewState.servers["0"]!))
            .applyPreviewModifiers(withState: viewState)
    }
}
