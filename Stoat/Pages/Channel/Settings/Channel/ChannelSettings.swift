//
//  ChannelSettiings.swift
//  Revolt
//
//  Created by Angelo on 08/01/2024.
//

import Foundation
import SwiftUI
import Types

struct ChannelSettings: View {
    @EnvironmentObject var viewState: ViewState
    @Environment(\.dismiss) var dismiss
    
    @Binding var server: Server?
    @Binding var channel: Channel
    @State var showDeleteChannelDialog = false
    @State var isDeletingChannel = false
    @State var deletionError: String?

    func deleteChannel() async {
        guard !isDeletingChannel else { return }

        isDeletingChannel = true
        deletionError = nil
        defer { isDeletingChannel = false }

        do {
            let _ = try await viewState.http.deleteChannel(channel: channel.id).get()
            viewState.removeChannelFromState(id: channel.id)
            dismiss()
        } catch let e {
            deletionError = e.localizedDescription
        }
    }
    
    var body: some View {
        List {
            Section("Settings") {
                NavigationLink {
                    ChannelOverviewSettings.fromState(viewState: viewState, channel: $channel)
                } label: {
                    Image(systemName: "info.circle.fill")
                    Text("Overview")
                }
                
                NavigationLink {
                    ChannelPermissionsSettings(server: $server, channel: $channel)
                } label: {
                    Image(systemName: "list.bullet")
                    Text("Permissions")
                }
                
                if let server = Binding($server) {
                    NavigationLink {
                        ChannelWebhookSettings(server: server, channel: $channel)
                    } label: {
                        Image(systemName: "cloud.fill")
                        Text("Webhooks")
                    }
                }
            }
            .listRowBackground(viewState.theme.background2)
            
            Button {
                showDeleteChannelDialog = true
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                    Text(isDeletingChannel ? "Deleting channel..." : "Delete channel")
                }
                .foregroundStyle(.red)
            }
            .disabled(isDeletingChannel)
            .listRowBackground(viewState.theme.background2)

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
                ChannelIcon(channel: channel)
            }
        }
        .toolbarBackground(viewState.theme.topBar.color, for: .automatic)
        .confirmationDialog("Delete channel?", isPresented: $showDeleteChannelDialog) {
            Button("Delete channel", role: .destructive) {
                Task { await deleteChannel() }
            }
            .disabled(isDeletingChannel)

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete \(channel.name ?? "this channel").")
        }

    }
}

#Preview {
    @StateObject var viewState = ViewState.preview().applySystemScheme(theme: .light)
    let channel = Binding($viewState.channels["0"])!
    let server = $viewState.servers["0"]
    
    return NavigationStack {
        ChannelSettings(server: server, channel: channel)
    }.applyPreviewModifiers(withState: viewState)
}
