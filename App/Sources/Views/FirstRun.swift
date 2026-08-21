import SwiftUI
import EndlessFrontierCore

/// **The first two minutes.**
///
/// The game had no introduction of any kind: a new player was put in a village
/// with a build bar and left to work out, on their own, four things that are
/// not guessable and each of which costs an hour to learn the hard way —
///
/// - that a **tick is two real minutes**, so nothing is meant to be watched,
///   and the world keeps going while the phone is in a pocket;
/// - that the **council runs the colony in the gaps**, so a player who touches
///   nothing still has a town, and micromanagement is a choice rather than a
///   requirement;
/// - that **food is a chain and not a number** — a plot ripens, a farmer reaps
///   it, a hauler carries it in, a cook makes a meal of it — so a granary full
///   of grain and a colony starving is a *correct* state with a fix;
/// - that **everything drawn is really there**: the birch, the boar, the woman
///   walking to the well all answer when tapped, because the canvas draws the
///   simulation rather than illustrating it.
///
/// Deliberately not a tutorial with arrows. This game's whole proposition is
/// that it goes on without you, and a sequence of hand-holding steps would be
/// making a promise the rest of it does not keep. Four cards, in the game's own
/// voice, then out of the way for good.
///
/// **Presentation only** (rule 5): the flag lives in `@AppStorage`, not on
/// `WorldState`. Whether somebody has read an introduction is a fact about the
/// person, not about the world — and a world exported, shared or rolled back
/// must not un-teach them.
struct FirstRunView: View {
    @Binding var isPresented: Bool

    @State private var page = 0

    private var cs: Bool { AppStrings.language == .cs }

    var body: some View {
        ZStack {
            Theme.ink.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                card
                Spacer(minLength: 0)
                controls
            }
            .padding(24)
        }
        .transition(.opacity)
    }

    // MARK: - The cards

    private var pages: [Page] { cs ? Page.czech : Page.english }

    private var card: some View {
        let entry = pages[min(page, pages.count - 1)]
        return VStack(alignment: .leading, spacing: 18) {
            Image(systemName: entry.symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.accent)
            Text(entry.title)
                .font(.system(.title2, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.text)
            Text(entry.body)
                .font(.system(.callout, design: .serif))
                .foregroundStyle(Theme.textDim)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 460, alignment: .leading)
        // Keyed by page so the text cross-fades rather than snapping, and so
        // VoiceOver reads the new card instead of announcing nothing.
        .id(page)
        .transition(.opacity)
    }

    // MARK: - Getting on with it

    private var controls: some View {
        VStack(spacing: 18) {
            HStack(spacing: 7) {
                ForEach(pages.indices, id: \.self) { index in
                    Circle()
                        .fill(index == page ? Theme.accent : Theme.textDim.opacity(0.35))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)

            Button {
                advance()
            } label: {
                Text(isLast ? (cs ? "Začít" : "Begin")
                            : (cs ? "Dál" : "Next"))
                    .font(.system(.callout, design: .serif).weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent.opacity(0.22),
                                in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)

            // Always available. Somebody starting their second colony should
            // not have to read this again to reach the game.
            Button {
                finish()
            } label: {
                Text(cs ? "Přeskočit" : "Skip")
                    .font(.caption)
                    .foregroundStyle(Theme.textDim)
            }
            .buttonStyle(.plain)
            .opacity(isLast ? 0 : 1)
            .disabled(isLast)
        }
        .frame(maxWidth: 460)
    }

    private var isLast: Bool { page >= pages.count - 1 }

    private func advance() {
        if isLast { finish() } else { withAnimation(.easeInOut(duration: 0.22)) { page += 1 } }
    }

    private func finish() {
        withAnimation(.easeInOut(duration: 0.25)) { isPresented = false }
    }

    // MARK: - What it says

    struct Page {
        let symbol: String
        let title: String
        let body: String

        /// Written twice rather than translated once. The Czech is the register
        /// the rest of the game is in — plain, concrete, a little dry — and a
        /// sentence built for English and then carried across reads like one.
        static let english: [Page] = [
            Page(symbol: "hourglass",
                 title: "The world does not wait",
                 body: """
                 A tick is two real minutes and a year is two hours, so nothing here is meant \
                 to be watched. Put the phone down: the colony goes on without you, and it will \
                 run up to a month of its own history before you come back to it.
                 """),
            Page(symbol: "person.3",
                 title: "A council runs it in the gaps",
                 body: """
                 Nobody is waiting for your orders. The council studies what it can reach, keeps \
                 the timber coming, and raises whatever the colony is shortest of — so a player \
                 who touches nothing still has a town in fifty years. What you decide, you \
                 decide because you wanted to, not because the place stops without you.
                 """),
            Page(symbol: "leaf",
                 title: "Food is a chain, not a number",
                 body: """
                 A plot ripens with the season. A farmer reaps it, and the grain lies where it \
                 fell until somebody carries it in. Then a cook makes a meal of it — and a meal \
                 is the only thing anybody can eat. A full granary and a hungry colony is not a \
                 bug: it means you have no cook.
                 """),
            Page(symbol: "hand.tap",
                 title: "Everything you can see is really there",
                 body: """
                 The birch, the boar, the woman walking to the well: tap any of them and they \
                 answer for themselves. The picture is not an illustration of the simulation — \
                 it is the simulation, drawn.
                 """)
        ]

        static let czech: [Page] = [
            Page(symbol: "hourglass",
                 title: "Svět na tebe nečeká",
                 body: """
                 Jeden tik jsou dvě skutečné minuty, rok jsou dvě hodiny. Nic z toho se nemá \
                 sledovat. Odlož telefon — osada běží dál bez tebe a než se vrátíš, prožije \
                 klidně měsíc vlastních dějin.
                 """),
            Page(symbol: "person.3",
                 title: "V mezerách vládne rada",
                 body: """
                 Nikdo nečeká na tvoje rozkazy. Rada bádá, co dosáhne, hlídá, aby bylo dřevo, \
                 a staví to, čeho je nejmíň — takže i hráč, který se ničeho nedotkne, má za \
                 padesát let město. Co rozhodneš, rozhodneš proto, žes chtěl, ne proto, že by \
                 se to bez tebe zastavilo.
                 """),
            Page(symbol: "leaf",
                 title: "Jídlo je řetěz, ne číslo",
                 body: """
                 Záhon dozraje podle ročního období. Sedlák ho sklidí a obilí leží tam, kde \
                 padlo, dokud ho někdo neodnese. Teprve kuchař z něj uvaří jídlo — a jídlo je \
                 jediné, co se dá sníst. Plná sýpka a hladová osada není chyba: znamená to, že \
                 nemáš kuchaře.
                 """),
            Page(symbol: "hand.tap",
                 title: "Všechno, co vidíš, tam opravdu je",
                 body: """
                 Bříza, kanec, žena jdoucí ke studni — klepni na cokoli a odpoví ti to samo za \
                 sebe. Obrázek není ilustrace simulace. Je to simulace, nakreslená.
                 """)
        ]
    }
}
