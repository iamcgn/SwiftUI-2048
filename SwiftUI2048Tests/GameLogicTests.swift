//
//  GameLogicTests.swift
//  SwiftUI2048 (portable port)
//
//  The game's rules as upstream wrote them, pinned by tests — including the quirks the
//  upstream README warns about ("the game algorithm may have issues"). The port keeps every
//  one of them: these tests describe the algorithm, they do not correct it. What a fix would
//  look like is in README.md, "Upstream's algorithm". The boards come in through the port's
//  two seams on GameLogic: `init(board:randomIndex:)` lays a board out, `randomIndex` chooses
//  where new blocks land in place of the system's random source.
//

import Testing
import Combine
@testable import SwiftUI2048

/// A chooser that picks the given indexes in turn (then the first blank), and remembers the
/// ranges it was asked to choose from.
final class Chooser {
    var picks: [Int]
    var asked: [Range<Int>] = []
    init(_ picks: [Int] = []) { self.picks = picks }
    func choose(_ range: Range<Int>) -> Int {
        asked.append(range)
        return picks.isEmpty ? range.lowerBound : picks.removeFirst()
    }
}

/// A chooser that always picks the last index: the new blocks take the last blank and (the
/// taken one swapped with the last, which is itself) the one before it — the bottom-right
/// corner, out of the way of a row under test.
func lastBlank(_ range: Range<Int>) -> Int { range.upperBound - 1 }

/// A board from rows of numbers (0 for blank); the blocks' ids are their row-major index + 100.
func board(_ rows: [[Int]]) -> GameLogic.BlockMatrixType {
    var matrix = GameLogic.BlockMatrixType()
    for (y, row) in rows.enumerated() {
        for (x, number) in row.enumerated() where number != 0 {
            matrix.place(IdentifiedBlock(id: 100 + y * 4 + x, number: number), to: (x, y))
        }
    }
    return matrix
}

/// The board as rows of numbers, 0 for blank.
func rows(_ logic: GameLogic) -> [[Int]] {
    (0..<4).map { y in (0..<4).map { x in logic.blockMatrix[(x, y)]?.number ?? 0 } }
}

/// The ids on the board, row-major.
func ids(_ logic: GameLogic) -> [Int: Int] {
    var result: [Int: Int] = [:]
    for block in logic.blockMatrix.flatten { result[block.index.1 * 4 + block.index.0] = block.item.id }
    return result
}

@Suite struct NewGameTests {

    @Test func aNewGameHasTwoBlocksOfTwoWhereTheChooserPutThem() {
        // The chooser is asked for an index into the 16 blanks, then into the 15 left (the one
        // taken is swapped with the last, upstream's way of removing it).
        let chooser = Chooser([5, 2])
        let logic = GameLogic(randomIndex: chooser.choose)
        #expect(chooser.asked == [0..<16, 0..<15])
        // Blank 5 is (1,1); after the swap the list is [0,1,2,3,4,15,6,...], so index 2 is (2,0).
        #expect(rows(logic) == [[0, 0, 2, 0], [0, 2, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        #expect(logic.lastGestureDirection == .up)
    }

    @Test func newBlocksAreAlwaysTwosNeverFours() {
        let logic = GameLogic(randomIndex: Chooser().choose)
        for _ in 0..<20 {
            logic.newGame()
            #expect(logic.blockMatrix.flatten.map(\.item.number) == [2, 2])
        }
    }

    @Test func choosingTheFirstIndexTwiceLandsOnTheFirstAndTheLastBlank() {
        // Upstream removes the first taken blank by overwriting it with the last one: a second
        // pick of index 0 is therefore the last blank, not the second.
        let logic = GameLogic(randomIndex: Chooser().choose)
        #expect(rows(logic) == [[2, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 2]])
    }

    @Test func newGameGivesFreshIdsAndResetsTheDirection() {
        let logic = GameLogic(randomIndex: Chooser().choose)
        logic.move(.right)
        #expect(logic.lastGestureDirection == .right)
        let before = Set(logic.blockMatrix.flatten.map(\.item.id))
        logic.newGame()
        let after = Set(logic.blockMatrix.flatten.map(\.item.id))
        #expect(after.isDisjoint(with: before))
        #expect(after.min()! > before.max()!)
        #expect(logic.lastGestureDirection == .up)
    }
}

@Suite struct MoveTests {

    /// A single block slides to the edge in every direction; two new 2s land where the
    /// chooser says (here: the first and, after the swap, the last blank).
    @Test(arguments: [
        (GameLogic.Direction.left, [[0, 0, 0, 0], [4, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]),
        (.right, [[0, 0, 0, 0], [0, 0, 0, 4], [0, 0, 0, 0], [0, 0, 0, 0]]),
        (.up, [[0, 0, 4, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]),
        (.down, [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 4, 0]]),
    ])
    func aBlockSlidesToTheEdge(direction: GameLogic.Direction, expected: [[Int]]) {
        let logic = GameLogic(board: board([[0, 0, 0, 0], [0, 0, 4, 0], [0, 0, 0, 0], [0, 0, 0, 0]]), randomIndex: Chooser().choose)
        logic.move(direction)
        var withSpawns = expected
        // The first blank in row-major order, and the last.
        let blanks = (0..<16).filter { expected[$0 / 4][$0 % 4] == 0 }
        withSpawns[blanks.first! / 4][blanks.first! % 4] = 2
        withSpawns[blanks.last! / 4][blanks.last! % 4] = 2
        #expect(rows(logic) == withSpawns)
        #expect(logic.lastGestureDirection == direction)
    }

    @Test func aSlidingBlockKeepsItsIdentity() {
        let logic = GameLogic(board: board([[0, 0, 0, 0], [0, 0, 4, 0], [0, 0, 0, 0], [0, 0, 0, 0]]), randomIndex: Chooser().choose)
        let id = logic.blockMatrix[(2, 1)]!.id
        logic.move(.left)
        #expect(logic.blockMatrix[(0, 1)]?.id == id)
    }

    @Test func aBlockAlreadyAtTheEdgeIsNoMoveAndSpawnsNothing() {
        let chooser = Chooser()
        let logic = GameLogic(board: board([[2, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]), randomIndex: chooser.choose)
        logic.move(.left)
        logic.move(.up)
        #expect(rows(logic) == [[2, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        #expect(chooser.asked.isEmpty)
        // The direction is recorded even for a move that moved nothing.
        #expect(logic.lastGestureDirection == .up)
    }
}

@Suite struct MergeTests {

    /// The two rows under test after a horizontal move; the spawns land in row 3 (`lastBlank`).
    func after(_ direction: GameLogic.Direction, _ top: [[Int]]) -> [[Int]] {
        let logic = GameLogic(board: board(top + [[0, 0, 0, 0], [0, 0, 0, 0]]), randomIndex: lastBlank)
        logic.move(direction)
        return Array(rows(logic).prefix(2))
    }

    @Test func equalNeighboursMergeOnceEach() {
        #expect(after(.left, [[2, 2, 2, 2], [4, 4, 8, 8]]) == [[4, 4, 0, 0], [8, 16, 0, 0]])
        #expect(after(.right, [[2, 2, 2, 2], [4, 4, 8, 8]]) == [[0, 0, 4, 4], [0, 0, 8, 16]])
    }

    @Test func aMergedBlockDoesNotMergeAgainInTheSameMove() {
        // 4, 2, 2 → 4, 4 (not 8): the new 4 is marked merged and stays.
        #expect(after(.left, [[4, 2, 2, 0], [0, 0, 0, 0]]) == [[4, 4, 0, 0], [0, 0, 0, 0]])
        #expect(after(.right, [[0, 2, 2, 4], [0, 0, 0, 0]]) == [[0, 0, 4, 4], [0, 0, 0, 0]])
    }

    @Test func threeEqualBlocksMergeAtTheLeadingEnd() {
        // Left and up merge the first pair; right and down the last.
        #expect(after(.left, [[2, 2, 2, 0], [0, 0, 0, 0]]) == [[4, 2, 0, 0], [0, 0, 0, 0]])
        #expect(after(.right, [[0, 2, 2, 2], [0, 0, 0, 0]]) == [[0, 0, 2, 4], [0, 0, 0, 0]])
    }

    @Test func blocksMergeAcrossBlanks() {
        #expect(after(.left, [[2, 0, 0, 2], [0, 4, 0, 4]]) == [[4, 0, 0, 0], [8, 0, 0, 0]])
    }

    @Test func unequalNeighboursDoNotMerge() {
        #expect(after(.left, [[2, 4, 2, 4], [0, 0, 0, 0]]) == [[2, 4, 2, 4], [0, 0, 0, 0]])
    }

    @Test func columnsMergeTheSameWay() {
        let logic = GameLogic(board: board([[2, 0, 0, 0], [2, 0, 0, 0], [2, 0, 0, 0], [0, 0, 0, 0]]), randomIndex: lastBlank)
        logic.move(.up)
        #expect(rows(logic).map { $0[0] } == [4, 2, 0, 0])
        let down = GameLogic(board: board([[0, 0, 0, 0], [2, 0, 0, 0], [2, 0, 0, 0], [2, 0, 0, 0]]), randomIndex: lastBlank)
        down.move(.down)
        #expect(rows(down).map { $0[0] } == [0, 0, 2, 4])
    }

    @Test func theMergedBlockIsTheOneThatMoved() {
        // Upstream doubles the block that slides into its partner (the later one in the merge
        // order) and keeps its id, so that is the block the animation carries.
        let logic = GameLogic(board: board([[2, 2, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]), randomIndex: Chooser().choose)
        let leftId = logic.blockMatrix[(0, 0)]!.id, rightId = logic.blockMatrix[(1, 0)]!.id
        logic.move(.left)
        #expect(logic.blockMatrix[(0, 0)]?.id == rightId)
        let other = GameLogic(board: board([[2, 2, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]), randomIndex: Chooser().choose)
        other.move(.right)
        #expect(other.blockMatrix[(3, 0)]?.id == leftId)
    }
}

@Suite struct SpawnTests {

    @Test func aMoveSpawnsExactlyTwoTwosAtTheChosenBlanks() {
        let chooser = Chooser([0, 0])
        let logic = GameLogic(board: board([[0, 2, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]), randomIndex: chooser.choose)
        logic.move(.left)
        // After the slide the blanks are the 15 squares other than (0,0); the first is (1,0),
        // the last (3,3).
        #expect(chooser.asked == [0..<15, 0..<14])
        #expect(rows(logic) == [[2, 2, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 2]])
        #expect(logic.blockMatrix.flatten.count == 3)
    }

    @Test func theTwoSpawnsNeverShareASquare() {
        // The taken blank is swapped out before the second pick: index 0 again is another square.
        for picks in [[0, 0], [3, 3], [14, 13], [7, 0]] {
            let logic = GameLogic(randomIndex: Chooser(picks).choose)
            #expect(logic.blockMatrix.flatten.count == 2, "picks \(picks)")
        }
    }

    @Test func quirkASwipeThatChangesNothingStillSpawnsWhenALineHoldsTwoBlocks() {
        // Upstream decides "moved" by comparing the new line against a snapshot that is not
        // aligned with the squares (every block is followed by an extra nil in the snapshot), so
        // a line of two or more blocks that cannot move still counts as moved and two blocks
        // spawn. A README-documented quirk, kept as upstream has it.
        let chooser = Chooser()
        let logic = GameLogic(board: board([[2, 4, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]), randomIndex: chooser.choose)
        logic.move(.left)
        #expect(chooser.asked.count == 2)
        #expect(rows(logic) == [[2, 4, 2, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 2]])
        // The same board swiped up: each column holds one block, nothing moves, nothing spawns.
        let columns = Chooser()
        let up = GameLogic(board: board([[2, 4, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]), randomIndex: columns.choose)
        up.move(.up)
        #expect(columns.asked.isEmpty)
        #expect(rows(up) == [[2, 4, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
    }

    @Test func quirkNothingSpawnsWithFewerThanTwoBlanks() {
        // 15 blocks and one blank: the move happens, no block spawns (upstream needs two blanks).
        let chooser = Chooser()
        let logic = GameLogic(board: board([[2, 4, 8, 16], [32, 64, 128, 256], [2, 4, 8, 16], [32, 64, 128, 0]]), randomIndex: chooser.choose)
        logic.move(.right)
        #expect(rows(logic) == [[2, 4, 8, 16], [32, 64, 128, 256], [2, 4, 8, 16], [0, 32, 64, 128]])
        #expect(chooser.asked.isEmpty)
        // A full board whose move merges one pair leaves one blank: still no spawn.
        let merging = GameLogic(board: board([[2, 2, 8, 16], [32, 64, 128, 256], [2, 4, 8, 16], [32, 64, 128, 256]]), randomIndex: chooser.choose)
        merging.move(.left)
        #expect(rows(merging)[0] == [4, 8, 16, 0])
        #expect(chooser.asked.isEmpty)
    }

    @Test func quirkTheGameNeverEnds() {
        // A full board with no equal neighbours: every direction leaves it as it is, with no
        // signal that the game is over (upstream has no score, win or game-over state).
        let full = [[2, 4, 8, 16], [32, 64, 128, 256], [2, 4, 8, 16], [32, 64, 128, 256]]
        let logic = GameLogic(board: board(full), randomIndex: Chooser().choose)
        for direction in [GameLogic.Direction.left, .right, .up, .down] {
            logic.move(direction)
            #expect(rows(logic) == full)
            #expect(logic.lastGestureDirection == direction)
        }
    }
}

@Suite struct PublishingTests {

    @Test func aMoveThatMovesPublishesTwiceANoMoveOnce() {
        // Upstream sends objectWillChange from `move` and again from `generateNewBlocks`.
        var sends = 0
        let moving = GameLogic(board: board([[0, 2, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]), randomIndex: lastBlank)
        let token = moving.objectWillChange.sink { _ in sends += 1 }
        moving.move(.left)
        #expect(sends == 2)
        token.cancel()
        sends = 0
        let still = GameLogic(board: board([[2, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]), randomIndex: lastBlank)
        let other = still.objectWillChange.sink { _ in sends += 1 }
        still.move(.left)
        #expect(sends == 1)
        other.cancel()
    }

    @Test func quirkObjectWillChangeFiresAfterTheBoardHasChanged() {
        // Upstream sends from `defer` blocks, so by the time a subscriber hears "will change"
        // the board already has. SwiftUI re-reads on the next turn either way.
        let logic = GameLogic(board: board([[0, 2, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]), randomIndex: lastBlank)
        var seen: [[[Int]]] = []
        let token = logic.objectWillChange.sink { seen.append(rows($0)) }
        logic.move(.left)
        token.cancel()
        #expect(seen.first?[0] == [2, 0, 0, 0])
    }
}
