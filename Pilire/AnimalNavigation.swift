import SceneKit

/// Cardinal movement gives the pet a shortest route without cutting building corners.
struct AnimalCell: Hashable {
    let col: Int
    let row: Int

    var neighbors: [AnimalCell] {
        [AnimalCell(col: col + 1, row: row), AnimalCell(col: col - 1, row: row),
         AnimalCell(col: col, row: row + 1), AnimalCell(col: col, row: row - 1)]
    }
}

enum AnimalNavigation {
    /// The town's walkability closure also bounds the search to the island.
    /// Paths omit the start cell; an empty path means the pet is already there.
    static func route(from start: AnimalCell, to goals: Set<AnimalCell>,
                      isWalkable: (AnimalCell) -> Bool) -> [AnimalCell]? {
        guard !goals.isEmpty else { return nil }
        if goals.contains(start) { return [] }
        var queue = [start]
        var index = 0
        var visited: Set<AnimalCell> = [start]
        var previous: [AnimalCell: AnimalCell] = [:]
        while index < queue.count {
            let cell = queue[index]
            index += 1
            for next in cell.neighbors where !visited.contains(next) && isWalkable(next) {
                visited.insert(next)
                previous[next] = cell
                if goals.contains(next) {
                    var path = [next]
                    var cursor = next
                    while let parent = previous[cursor], parent != start {
                        path.append(parent)
                        cursor = parent
                    }
                    return path.reversed()
                }
                queue.append(next)
            }
        }
        return nil
    }
}

/// A fixed doorway plus a validity check, so moved/removed houses cannot leave
/// a pet walking towards an obsolete bed. The weak scene/node check is supplied by TownScene.
struct AnimalKennelDestination {
    let id: ObjectIdentifier
    let cell: AnimalCell
    let entrance: AnimalCell
    let world: SCNVector3
    let yaw: Float
    let isValid: () -> Bool
}
