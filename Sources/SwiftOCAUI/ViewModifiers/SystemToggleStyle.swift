import SwiftUI

// https://www.appcoda.com/swiftui-togglestyle/
struct SymbolToggleStyle: ToggleStyle {
    var systemImage: String = "speaker.slash.circle"
    var activeColor: Color = .green

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label

            Spacer()

            RoundedRectangle(cornerRadius: 30)
                .fill(configuration.isOn ? activeColor : Color(.systemGray))
                .overlay {
                    Circle()
                        .fill(.white)
                        .padding(3)
                        .overlay {
                            Image(systemName: systemImage)
                                .foregroundColor(
                                    configuration
                                        .isOn ? activeColor : Color(.systemGray)
                                )
                        }
                        .offset(x: configuration.isOn ? 10 : -10)
                }
                .frame(width: 50, height: 32)
                .onTapGesture {
                    withAnimation(.spring()) {
                        configuration.isOn.toggle()
                    }
                }
        }
    }
}
