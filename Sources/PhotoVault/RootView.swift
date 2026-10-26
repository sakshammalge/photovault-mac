import SwiftUI

struct RootView: View {
    private enum Tab { case gallery, device }
    @State private var tab = Tab.gallery

    var body: some View {
        Group {
            switch tab {
            case .gallery: GalleryView()
            case .device: DeviceView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $tab) {
                    Text("Gallery").tag(Tab.gallery)
                    Text("iPhone").tag(Tab.device)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        }
    }
}
