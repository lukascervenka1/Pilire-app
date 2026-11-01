import Foundation

@main
struct MarketChecks {
    @MainActor static func main() {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        var previousStories: [Int: String] = [:]
        func kind(_ offer: Market.Offer) -> Int {
            switch (offer.give, offer.get) {
            case (.material, .coins): 0
            case (.material, .material): 1
            default: 2
            }
        }
        for offset in 0..<365 {
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            let later = calendar.date(byAdding: .hour, value: 20, to: day)!
            let offers = Market.offers(on: day, hasMarketHall: true)
            let repeated = Market.offers(on: later, hasMarketHall: true)
            let withoutHall = Market.offers(on: day, hasMarketHall: false)
            precondition(offers.count == 3 && withoutHall.count == 2)
            precondition(Set(offers.map(kind)).count == 3)
            precondition(Set(offers.map(\.id)).count == 3)
            for (index, offer) in offers.enumerated() {
                precondition(offer.id == repeated[index].id && offer.give == repeated[index].give && offer.get == repeated[index].get)
                precondition(offer.story.cs == repeated[index].story.cs)
                if index < 2 {
                    precondition(offer.id == withoutHall[index].id && offer.give == withoutHall[index].give && offer.get == withoutHall[index].get)
                }
                let style = kind(offer)
                precondition(previousStories[style] != offer.story.cs, "Repeated story on consecutive days")
                previousStories[style] = offer.story.cs
                if case .material(let from, let amount) = offer.give {
                    precondition(amount > 0)
                    if case .material(let to, let received) = offer.get { precondition(from != to && received > 0) }
                }
            }
            precondition(Market.deal(on: day) == Market.deal(on: later))
            for material in Material.allCases {
                precondition(Market.buyPrice(material, on: day) > Market.sellPrice(material, hasMarketHall: true, on: day))
            }
        }

        // This executable has its own defaults domain; preserve any earlier run.
        let oldClaims = UserDefaults.standard.object(forKey: "marketClaimedOffers")
        defer { UserDefaults.standard.set(oldClaims, forKey: "marketClaimedOffers") }
        UserDefaults.standard.removeObject(forKey: "marketClaimedOffers")
        let settings = UserSettings()
        let offer = Market.offers(on: start, hasMarketHall: true).first!
        precondition(!Market.accept(offer, settings, on: start), "An unaffordable request was accepted")
        settings.coinBalance = 10_000
        for material in Material.allCases { settings.add(material, 1_000) }
        func balances() -> [Int] { [settings.coinBalance] + Material.allCases.map { settings.count($0) } }
        let before = balances()
        precondition(Market.accept(offer, settings, on: start))
        precondition(Market.isClaimed(offer) && balances() != before)
        let after = balances()
        precondition(!Market.accept(offer, settings, on: start) && balances() == after, "Request was paid twice")
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start)!
        let unclaimedOldOffer = Market.offers(on: start, hasMarketHall: true)[1]
        precondition(!Market.accept(unclaimedOldOffer, settings, on: tomorrow) && balances() == after,
                     "Yesterday's request was accepted after midnight")
        precondition(Market.accept(Market.offers(on: tomorrow, hasMarketHall: true)[1], settings, on: tomorrow))
        // Story pools: complete in all languages, each story used once per cycle.
        let pools = [S.market.storiesForCoins, S.market.storiesSwap, S.market.storiesSurplus]
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        for pool in pools {
            precondition(pool.count >= 12 && gcd(pool.count, Market.storyStride) == 1,
                         "Pool size must be coprime with the stride or some stories never appear")
            precondition(Set(pool.map(\.cs)).count == pool.count, "Duplicate story")
            for story in pool {
                for text in [story.cs, story.sk, story.en] {
                    precondition(text.components(separatedBy: "%1$@").count == 2
                                 && text.components(separatedBy: "%2$@").count == 2, "Bad placeholders: \(text)")
                    let out = String(format: text, "GIVE", "GET")
                    precondition(out.contains("GIVE") && out.contains("GET") && !out.contains("%"), out)
                }
            }
        }
        for style in 0..<3 {
            for startDay in stride(from: 0, to: 365, by: 7) {
                let window = (0..<12).map { offset -> Int in
                    let day = calendar.date(byAdding: .day, value: startDay + offset, to: start)!
                    return Market.storyIndex(on: day, style: style, count: 12)
                }
                precondition(Set(window).count == 12, "A story came back within 12 days")
            }
        }

        // Economy: the trader is a daily bonus, never a money printer. Measure
        // the most a player could gain per day by taking every request and
        // settling the difference at the counter, and check the counter alone
        // can't be looped for profit.
        var dailyGain: [Int] = []
        for offset in 0..<365 {
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            var gain = 0
            for offer in Market.offers(on: day, hasMarketHall: true) {
                func value(_ p: Market.Payment, buying: Bool) -> Int {
                    switch p {
                    case .coins(let n): n
                    case .material(let m, let n):
                        n * (buying ? Market.buyPrice(m, on: day) : Market.sellPrice(m, hasMarketHall: true, on: day))
                    }
                }
                gain += value(offer.get, buying: false) - value(offer.give, buying: true)
            }
            dailyGain.append(gain)
            for a in Material.allCases {
                for b in Material.allCases where a != b {
                    let cost = Market.swapCost(from: a, to: b, hasMarketHall: true, on: day)
                    precondition(cost * Market.sellPrice(a, hasMarketHall: true, on: day) >= Market.buyPrice(b, on: day),
                                 "Swap is cheaper than selling and buying")
                    precondition(Market.swapCost(from: b, to: a, hasMarketHall: true, on: day) * cost > 1,
                                 "Swapping back and forth gains material")
                }
            }
        }
        precondition(dailyGain.max()! <= 150, "Trader requests pay out more than a small daily bonus")
        print("Trader bonus per day if every request is flipped at the counter: max \(dailyGain.max()!), "
              + "average \(dailyGain.reduce(0, +) / dailyGain.count) coins.")

        print("Market checks passed: 365 stable days, varied requests, market-hall continuity, claim once, shortages, midnight boundary, story pools and economy.")
    }
}
