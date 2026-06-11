//
//  ServerMembersSettings.swift
//  Stoat
//

import SwiftUI
import Types

struct ServerMembersSettings: View {
    @EnvironmentObject var viewState: ViewState

    @Binding var server: Server

    @State var members: [Member]?
    @State var users: [String: User] = [:]
    @State var searchText = ""
    @State var error: String?

    let joinedFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter
    }()

    func filteredMembers() -> [(member: Member, user: User)] {
        let rows = (members ?? [])
            .compactMap { member in users[member.id.user].map { (member, $0) } }
            .sorted { lhs, rhs in
                (lhs.1.display_name ?? lhs.1.username).localizedCaseInsensitiveCompare(rhs.1.display_name ?? rhs.1.username) == .orderedAscending
            }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return rows }

        return rows.filter { member, user in
            user.username.lowercased().contains(query)
            || (user.display_name?.lowercased().contains(query) ?? false)
            || (member.nickname?.lowercased().contains(query) ?? false)
        }
    }

    func fetchMembers() async {
        do {
            let response = try await viewState.http.fetchMembers(server: server.id, excludeOffline: false).get()

            for user in response.users {
                users[user.id] = user
                viewState.users[user.id] = user
            }

            if viewState.members[server.id] == nil {
                viewState.members[server.id] = [:]
            }

            for member in response.members {
                viewState.members[server.id]?[member.id.user] = member
            }

            members = response.members
            error = nil
        } catch let e {
            error = e.localizedDescription
        }
    }

    func joinedDateText(_ member: Member) -> Text {
        if let joined = joinedFormatter.date(from: member.joined_at) {
            return Text(joined, style: .date)
        }

        return Text("Unknown join date")
    }

    var body: some View {
        Group {
            if let error {
                Text(verbatim: error)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if members != nil {
                List {
                    let rows = filteredMembers()

                    Section("Members - \(rows.count)") {
                        ForEach(rows, id: \.member.id) { member, user in
                            Button {
                                viewState.openUserSheet(user: user, member: member)
                            } label: {
                                HStack(spacing: 12) {
                                    Avatar(user: user, member: member, withPresence: true)
                                        .frame(width: 36, height: 36)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(verbatim: member.nickname ?? user.display_name ?? user.username)
                                            .font(.headline)
                                            .lineLimit(1)

                                        HStack(spacing: 4) {
                                            Text(verbatim: "@\(user.username)")

                                            if let roles = member.roles, !roles.isEmpty {
                                                Text("•")
                                                Text("\(roles.count) roles")
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(viewState.theme.foreground2)
                                    }

                                    Spacer()

                                    joinedDateText(member)
                                        .font(.caption)
                                        .foregroundStyle(viewState.theme.foreground2)
                                }
                            }
                        }
                    }
                    .listRowBackground(viewState.theme.background2)
                }
                .searchable(text: $searchText)
                .scrollContentBackground(.hidden)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .background(viewState.theme.background)
        .navigationTitle("Members")
        .toolbarBackground(viewState.theme.topBar.color, for: .automatic)
        .task {
            await fetchMembers()
        }
        .refreshable {
            await fetchMembers()
        }
    }
}

