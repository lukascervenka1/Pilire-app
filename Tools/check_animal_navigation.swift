// Run: swiftc -module-cache-path /private/tmp/pilire-swift-cache \
// Pilire/AnimalNavigation.swift Tools/check_animal_navigation.swift \
// -o /private/tmp/pilire-navigation-check && /private/tmp/pilire-navigation-check
import Foundation

@main enum NavigationCheck {
    static func main() {
        let start = AnimalCell(col:1,row:1), goal = AnimalCell(col:4,row:1)
        var blocked = Set((0...5).map { AnimalCell(col:2,row:$0) })
        func land(_ cell: AnimalCell) -> Bool {
            (0..<7).contains(cell.col) && (0..<7).contains(cell.row) && !blocked.contains(cell)
        }
        let detour = AnimalNavigation.route(from:start,to:[goal],isWalkable:land)!
        precondition(detour.count == 13 && detour.last == goal)
        precondition(detour.allSatisfy(land))
        var previous = start
        for cell in detour {
            precondition(abs(cell.col-previous.col)+abs(cell.row-previous.row) == 1)
            previous = cell
        }
        blocked.insert(detour[0])
        let replanned = AnimalNavigation.route(from:start,to:[goal],isWalkable:land)!
        precondition(!replanned.contains(detour[0]) && replanned.last == goal)
        blocked.remove(detour[0])
        let nearest = AnimalNavigation.route(from:start,to:[goal,AnimalCell(col:1,row:3)],isWalkable:land)!
        precondition(nearest.count == 2)
        precondition(AnimalNavigation.route(from:start,to:[start],isWalkable:land)!.isEmpty)
        blocked.formUnion(goal.neighbors)
        precondition(AnimalNavigation.route(from:start,to:[goal],isWalkable:land) == nil)
        var corridor = Set<AnimalCell>()
        for row in stride(from:0,through:22,by:2) {
            for col in 0..<24 { corridor.insert(AnimalCell(col:col,row:row)) }
            if row < 22 { corridor.insert(AnimalCell(col:(row/2).isMultiple(of:2) ? 23 : 0,row:row+1)) }
        }
        let long = AnimalNavigation.route(from:AnimalCell(col:0,row:0),to:[AnimalCell(col:0,row:22)],isWalkable:corridor.contains)!
        precondition(long.count == 298)
        print("PASS: shortest detour, cardinal clearance, changed obstacles, closest goal, already arrived, unreachable, 298-tile route.")
    }
}
