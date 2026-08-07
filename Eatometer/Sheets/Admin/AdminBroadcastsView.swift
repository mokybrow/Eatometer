import SwiftUI

struct AdminBroadcastsView: View {
    @EnvironmentObject private var adminService: AdminService

    private let appOptions = AdminBroadcastAppOption.options

    @State private var newsletterSubject = ""
    @State private var newsletterBody = ""
    @State private var selectedSenderAppID = "eatometer-app"
    @State private var pushTitle = ""
    @State private var pushBody = ""
    @State private var pushNewsText = ""
    @State private var selectedAudienceAppID = "eatometer-app"

    var body: some View {
        Form {
            Section("Newsletter") {
                Picker("Mailbox", selection: $selectedSenderAppID) {
                    ForEach(appOptions) { option in
                        Text(option.senderTitle).tag(option.id)
                    }
                }
                .pickerStyle(.menu)

                TextField("Subject", text: $newsletterSubject)
                TextField("Body", text: $newsletterBody, axis: .vertical)
                    .lineLimit(5...10)

                Button {
                    Task {
                        let sent = await adminService.sendNewsletter(
                            subject: newsletterSubject,
                            body: newsletterBody,
                            appID: selectedSenderAppID
                        )
                        if sent != nil {
                            newsletterSubject = ""
                            newsletterBody = ""
                        }
                    }
                } label: {
                    if adminService.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Send Newsletter")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(adminService.isLoading || newsletterSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newsletterBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section("News Push") {
                Picker("Audience", selection: $selectedAudienceAppID) {
                    ForEach(appOptions) { option in
                        Text(option.audienceTitle).tag(option.id)
                    }
                }
                .pickerStyle(.menu)

                TextField("Title", text: $pushTitle)
                TextField("Body", text: $pushBody, axis: .vertical)
                    .lineLimit(3...8)
                TextField("News Text (optional)", text: $pushNewsText, axis: .vertical)
                    .lineLimit(3...8)

                Button {
                    Task {
                        let sent = await adminService.sendNewsPush(
                            title: pushTitle,
                            body: pushBody,
                            newsText: pushNewsText,
                            appID: selectedAudienceAppID
                        )
                        if sent != nil {
                            pushTitle = ""
                            pushBody = ""
                            pushNewsText = ""
                        }
                    }
                } label: {
                    if adminService.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Send News Push")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(adminService.isLoading || pushTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pushBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let success = adminService.lastSuccessMessage, !success.isEmpty {
                Section {
                    Text(success)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }

            if let error = adminService.lastErrorMessage, !error.isEmpty {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Broadcasts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AdminBroadcastAppOption: Identifiable {
    let id: String
    let name: String
    let mailbox: String
    let audienceTitle: String

    var senderTitle: String {
        "\(name) - \(mailbox)"
    }

    static let options = [
        AdminBroadcastAppOption(id: "eatometer-app", name: "Eatometer", mailbox: "news@goeatometer.com", audienceTitle: "Eatometer users")
    ]
}
