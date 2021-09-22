import Foundation
import XCTest
import Combine
import PromiseKit

class CombineTests: XCTestCase {
    var cancellables = [AnyCancellable]()

    func test_elementsContained() {
        XCTAssertTrue([1].elementsEqualRandomly(in: [1]))
        XCTAssertFalse([1].elementsEqualRandomly(in: []))
        XCTAssertFalse([1].elementsEqualRandomly(in: [1,2]))
        XCTAssertTrue([1,2].elementsEqualRandomly(in: [1]))
        XCTAssertTrue([1,2,1].elementsEqualRandomly(in: [1,1,2]))
    }

    func test_fulfillExpectationAtReceiveValue() {
        let exp = expectation(description: "")
        let sut = PassthroughSubject<Int, Never>()
        let cancellable = sut
            .sink(receiveValue: { _ in
                print("sink received")
                exp.fulfill()
            })
        sut.send(1)
        wait(for: [exp], timeout: 1)
    }

    func test_wait_extension() {
        let sut = Just(1).delay(for: .milliseconds(500), scheduler: DispatchQueue.main)
        let exp = sut.wait(for: 1).store(in: &cancellables)
        wait(for: [exp], timeout: 1)

        let sut2 = PassthroughSubject<Int, Never>()
        let exp2 = sut2.wait(for: 1).store(in: &cancellables)
        exp2.isInverted = true
        wait(for: [exp2], timeout: 0.1)

        let subject = PassthroughSubject<Int, Never>()
        let exp3 = subject.wait(for: 1, 2).store(in: &cancellables)
        subject.send(1)
        subject.send(2)
        wait(for: [exp3], timeout: 1)

        let exp4 = subject.wait(for: 3).store(in: &cancellables)
        subject.send(3)
        wait(for: [exp4], timeout: 1)
    }

    func test_anyPublisher_toPromise() {
        var cancellables = [AnyCancellable]()
        let subject = PassthroughSubject<Int, Never>()
        let promise = subject.eraseToAnyPublisher().toPromise(store: &cancellables)
        subject.send(1)
        XCTAssertEqual(promise.isFulfilled, true)
    }
}

class Mapper: ObservableObject {
    @Published private(set) var counter = 0
    @Published var string = ""

    init() {
        $string
            .map { newValue in
                newValue.count
            }
            .assign(to: &$counter)
    }
}

extension AnyPublisher {
    func toPromise<C>(store: inout C) -> Promise<Output> where C: RangeReplaceableCollection, C.Element == AnyCancellable {
        return Promise { resolver in
            sink(receiveCompletion: { _ in },
                               receiveValue: { output in resolver.fulfill(output) })
                .store(in: &store)
        }
    }
}

extension Sequence {
    func elementsEqualRandomly<OtherSequence>(in otherSequence: OtherSequence) -> Bool where OtherSequence: Sequence, OtherSequence.Element == Self.Element, Self.Element: Equatable {
        var remainingExpected = Array(otherSequence)
        if remainingExpected.count == 0 { return false }
        forEach { actualValue in
            if let matchingId = remainingExpected.firstIndex(of: actualValue){
                remainingExpected.remove(at: matchingId)
            } else {
                return
            }
        }
        return remainingExpected.count == 0 ? true : false
    }
}

