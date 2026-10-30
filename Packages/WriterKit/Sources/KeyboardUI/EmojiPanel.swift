#if canImport(UIKit)
import SwiftUI
import WritingCore

/// A compact emoji picker (custom keyboards can't show the system emoji keyboard inline).
struct EmojiPanel: View {
    @ObservedObject var controller: KeyboardController

    static let sections: [(title: String, emojis: [String])] = [
        ("Smileys", Array("😀😃😄😁😆😅😂🤣😊😇🙂🙃😉😌😍🥰😘😗😙😚😋😛😝😜🤪🤨🧐🤓😎🥳😏😒😞😔😟😕🙁😣😖😫😩🥺😢😭😤😠😡🤯😳🥵🥶😱😨😰😥😓🤗🤔🤭🤫🤥😶😐😑😬🙄😯😦😧😮😲🥱😴🤤😪😵🤐🥴🤢🤮🤧😷🤒🤕").map(String.init)),
        ("Gestures", Array("👍👎👌🤌🤏✌️🤞🤟🤘🤙👈👉👆👇☝️✋🤚🖐🖖👋👏🙌👐🤲🙏💪").map(String.init)),
        ("Hearts", Array("❤️🧡💛💚💙💜🖤🤍🤎💔❣️💕💞💓💗💖💘💝").map(String.init)),
        ("Objects", Array("🎉🎊🎁🎂🔥✨⭐️🌟💯✅❌⚠️📌📎📅📄📈💡💬☕️🍕🍺🥂🚀🏠💼📱💻").map(String.init)),
    ]

    var body: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(38), spacing: 4), count: 4), spacing: 4) {
                    ForEach(Self.sections, id: \.title) { section in
                        ForEach(section.emojis, id: \.self) { emoji in
                            Button { controller.insertEmoji(emoji) } label: {
                                Text(emoji).font(.system(size: 30)).frame(width: 40, height: 38)
                            }
                            .accessibilityIdentifier("kb.emoji.\(emoji)")
                        }
                    }
                }
                .padding(.horizontal, 6)
            }
            HStack {
                Button { controller.panel = .keys } label: {
                    Text("ABC").font(.system(size: 16)).frame(width: 58, height: 38)
                        .background(RoundedRectangle(cornerRadius: 5).fill(KeyboardStyle.specialKey))
                }
                .accessibilityIdentifier("kb.emoji.abc")
                Spacer()
                Button { controller.backspace() } label: {
                    Image(systemName: "delete.left").frame(width: 58, height: 38)
                        .background(RoundedRectangle(cornerRadius: 5).fill(KeyboardStyle.specialKey))
                }
                .accessibilityIdentifier("kb.emoji.delete")
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
        }
        .padding(.top, 8)
    }
}
#endif
