import Foundation
import Combine
import XCTest
import PlaygroundApp

class CacheableRequestTests: XCTestCase {
    var cancellables = [AnyCancellable]()

    struct TestError: Error, Equatable { }

    override func tearDown() {
        cancellables = []
    }

    func test_get_whenRequestIsNil_shouldComplete() {
        let sut = CacheableRequest<Int>(publisherGetter: { nil })

        let exp = XCTestExpectation(description: "Completion received")
        sut.get()
            .sink(receiveCompletion: { _ in exp.fulfill() },
                  receiveValue: { _ in })
            .store(in: &cancellables)

        wait(for: [exp], timeout: 1)
    }

    func test_get_whenValueFetched_shouldReturnValue() {
        let subject = PassthroughSubject<Int, Error>()
        let sut = CacheableRequest(publisherGetter: { subject.eraseToAnyPublisher() })

        let exp = sut.get().wait(for: 1)
            .store(in: &cancellables)
        subject.send(1)

        wait(for: [exp], timeout: 1)
    }

    func test_get_whenValueCached_shouldReturnSameValueToAllSubscribers() {
        let subject = PassthroughSubject<Int, Error>()
        let sut = CacheableRequest(publisherGetter: { subject.eraseToAnyPublisher() })

        sut.get().sink(receiveCompletion: { _ in }, receiveValue: { _ in })
            .store(in: &cancellables)
        subject.send(1)

        let exp = sut.get().wait(for: 1)
            .store(in: &cancellables)
        let exp2 = sut.get().wait(for: 1)
            .store(in: &cancellables)
        wait(for: [exp, exp2], timeout: 1)
    }

    func test_get_whenRequestInProgress_shouldSubscribeToExisiting() {
        var subscribeCount = 0
        let subject = PassthroughSubject<Int, Error>()
        subject.handleEvents(receiveSubscription: { _ in subscribeCount += 1 })
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
            .store(in: &cancellables)

        let sut = CacheableRequest(publisherGetter: { subject.eraseToAnyPublisher() })
        let exp = sut.get().wait(for: 1)
            .store(in: &cancellables)
        subject.send(1)

        wait(for: [exp], timeout: 1)
        XCTAssertEqual(subscribeCount, 1)
    }

    func test_get_whenRequestInProgressWithMultipleSubscribers_shouldSubscribeToExisiting() {
        var subscribeCount = 0
        let subject = PassthroughSubject<Int, Error>()
        subject.handleEvents(receiveSubscription: { _ in subscribeCount += 1 })
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
            .store(in: &cancellables)

        let sut = CacheableRequest(publisherGetter: { subject.eraseToAnyPublisher() })
        let exp = sut.get().wait(for: 1)
            .store(in: &cancellables)
        let exp2 = sut.get().wait(for: 1)
            .store(in: &cancellables)
        subject.send(1)

        wait(for: [exp, exp2], timeout: 1)
        XCTAssertEqual(subscribeCount, 1)
    }

    func test_get_whenPreviousRequestFailed_shouldStartNewRequest() {
        let error = TestError()
        var getCount = 0
        let publisherGetter: () -> AnyPublisher<Int, Error> = {
            getCount += 1
            if getCount == 1 {
                return Fail(error: error).eraseToAnyPublisher()
            } else {
                return Just(1).setFailureType(to: Error.self).eraseToAnyPublisher()
            }
        }
        let sut = CacheableRequest(publisherGetter: publisherGetter)

        let exp = sut.get().wait(for: error)
            .store(in: &cancellables)
        wait(for: [exp], timeout: 1)

        let exp2 = sut.get().wait(for: 1)
            .store(in: &cancellables)
        wait(for: [exp2], timeout: 1)
    }

    func test_get_whenValueFetchedAndForceRefreshCalled_shouldReturnNewValue() {
        var getCount = 0
        let publisherGetter: () -> AnyPublisher<Int, Error> = {
            getCount += 1
            if getCount == 1 {
                return Just(1).setFailureType(to: Error.self).eraseToAnyPublisher()
            } else {
                return Just(2).setFailureType(to: Error.self).eraseToAnyPublisher()
            }
        }

        let sut = CacheableRequest(publisherGetter: publisherGetter)
        let exp = sut.get().wait(for: 1)
            .store(in: &cancellables)
        let exp2 = sut.get(forceRefresh: true).wait(for: 2)
            .store(in: &cancellables)

        wait(for: [exp, exp2], timeout: 1)
    }

    func test_get_whenForceRefreshCalled_shouldReturnNewValueToAllSubscribers() {
        var getCount = 0
        let publisherGetter: () -> AnyPublisher<Int, Error> = {
            getCount += 1
            if getCount == 1 {
                return Just(1).setFailureType(to: Error.self).eraseToAnyPublisher()
            } else {
                return Just(2).setFailureType(to: Error.self).eraseToAnyPublisher()
            }
        }

        let sut = CacheableRequest(publisherGetter: publisherGetter)
        sut.get().sink(receiveCompletion: { _ in }, receiveValue: { _ in })
            .store(in: &cancellables)
        let exp = sut.get(forceRefresh: true).wait(for: 2)
            .store(in: &cancellables)
        let exp2 = sut.get(forceRefresh: true).wait(for: 2)
            .store(in: &cancellables)

        wait(for: [exp, exp2], timeout: 1)
    }

    func test_get_whenRequestFailedAndForceRefreshCalled_shouldReturnNewValue() {
        let error = TestError()
        var getCount = 0
        let publisherGetter: () -> AnyPublisher<Int, Error> = {
            getCount += 1
            if getCount == 1 {
                return Fail(error: error).eraseToAnyPublisher()
            } else {
                return Just(1).setFailureType(to: Error.self).eraseToAnyPublisher()
            }
        }

        let sut = CacheableRequest(publisherGetter: publisherGetter)
        let exp = sut.get().wait(for: error)
            .store(in: &cancellables)
        wait(for: [exp], timeout: 1)
        let exp2 = sut.get(forceRefresh: true).wait(for: 1)
            .store(in: &cancellables)
        wait(for: [exp2], timeout: 1)
    }

    func test_get_whenRequestInProgressAndForceRefreshCalled_shouldSubscribeToExisting() {
        let subject1 = PassthroughSubject<Int, Error>()
        let subject2 = PassthroughSubject<Int, Error>()
        var getCount = 0
        let publisherGetter: () -> AnyPublisher<Int, Error> = {
            getCount += 1
            if getCount == 1 {
                return subject1.eraseToAnyPublisher()
            } else {
                return subject2.eraseToAnyPublisher()
            }
        }

        let sut = CacheableRequest(publisherGetter: publisherGetter)
        let exp = sut.get().wait(for: 1)
            .store(in: &cancellables)
        let exp2 = sut.get(forceRefresh: true).wait(for: 1)
            .store(in: &cancellables)
        subject1.send(1)

        wait(for: [exp, exp2], timeout: 1)
    }

    func test_subscribe_whenValueCached_shouldReturnCachedValue() {
        var subscribeCount = 0
        let subject = PassthroughSubject<Int, Error>()
        subject.handleEvents(receiveSubscription: { _ in subscribeCount += 1 })
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
            .store(in: &cancellables)

        let sut = CacheableRequest(publisherGetter: { subject.eraseToAnyPublisher() })
        let exp = sut.get().wait(for: 1)
            .store(in: &cancellables)
        subject.send(1)
        let exp2 = sut.subscribe().wait(for: 1)
            .store(in: &cancellables)

        wait(for: [exp, exp2], timeout: 1)
        XCTAssertEqual(subscribeCount, 1)
    }

    func test_subscribe_whenCachedValueAndNewValueAreEmitted_shouldEmitTwoValues() {
        let subject = PassthroughSubject<Int, Error>()

        let sut = CacheableRequest(publisherGetter: { subject.eraseToAnyPublisher() })
        let exp = sut.get().wait(for: 1)
            .store(in: &cancellables)
        subject.send(1)
        let exp2 = sut.subscribe().wait(for: 1, 2)
            .store(in: &cancellables)
        subject.send(2)

        wait(for: [exp, exp2], timeout: 1)
    }

    func test_subscribe_whenRequestIsRefreshed_shouldEmitTwoValues() {
        var getCount = 0
        let publisherGetter: () -> AnyPublisher<Int, Error> = {
            getCount += 1
            switch getCount {
            case 1: return Just(1).setFailureType(to: Error.self).eraseToAnyPublisher()
            case 2: return Just(2).setFailureType(to: Error.self).eraseToAnyPublisher()
            default: XCTFail("Expected two calls to get publisher, but got \(getCount)")
                return Fail(error: TestError()).eraseToAnyPublisher()
            }
        }

        let sut = CacheableRequest(publisherGetter: publisherGetter)
        let exp = sut.subscribe().wait(for: 1, 2)
            .store(in: &cancellables)
        let exp2 = sut.get(forceRefresh: true).wait(for: 2)
            .store(in: &cancellables)

        wait(for: [exp, exp2], timeout: 1)
    }

    func test_subscribe_whenRequestFails_shouldNotFail() {
        var getCount = 0
        let publisherGetter: () -> AnyPublisher<Int, Error> = {
            getCount += 1
            switch getCount {
            case 1: return Fail(error: TestError()).eraseToAnyPublisher()
            case 2: return Just(2).setFailureType(to: Error.self).eraseToAnyPublisher()
            default: XCTFail("Expected two calls to get publisher, but got \(getCount)")
                return Fail(error: TestError()).eraseToAnyPublisher()
            }
        }

        let sut = CacheableRequest(publisherGetter: publisherGetter)
        let exp = sut.subscribe().wait(for: TestError())
            .store(in: &cancellables)
        exp.isInverted = true

        wait(for: [exp], timeout: 0.1)
    }

    func test_subscribe_whenSingleValueIsReturnedThenRequestFails_shouldReturnValueAndNotFail() {
        var getCount = 0
        let publisherGetter: () -> AnyPublisher<Int, Error> = {
            getCount += 1
            switch getCount {
            case 1: return Just(2).setFailureType(to: Error.self).eraseToAnyPublisher()
            case 2: return Fail(error: TestError()).eraseToAnyPublisher()
            default: XCTFail("Expected two calls to get publisher, but got \(getCount)")
                return Fail(error: TestError()).eraseToAnyPublisher()
            }
        }

        let sut = CacheableRequest(publisherGetter: publisherGetter)
        let subscribeValueExp = XCTestExpectation(description: "Value received")
        let subscribeErrorNotReceivedExp = XCTestExpectation(description: "Error received")
        subscribeErrorNotReceivedExp.isInverted = true
        sut.subscribe().sink(
            receiveCompletion: { completion in
                switch completion {
                case .failure(_): subscribeErrorNotReceivedExp.fulfill()
                case .finished: XCTFail("Subscribe should not complete as .finished")
                }
            },
            receiveValue: { _ in subscribeValueExp.fulfill() })
            .store(in: &cancellables)
        let expError = sut.get(forceRefresh: true).wait(for: TestError())
            .store(in: &cancellables)
        wait(for: [expError, subscribeValueExp, subscribeErrorNotReceivedExp], timeout: 0.1)
    }

    func test_subscribe_whenRequestIsNil_shouldNotComplete() {
        let sut = CacheableRequest<Int>(publisherGetter: { nil })

        let exp = XCTestExpectation(description: "Completion not received")
        exp.isInverted = true
        sut.subscribe()
            .sink(receiveCompletion: { _ in exp.fulfill() },
                  receiveValue: { _ in })
            .store(in: &cancellables)

        wait(for: [exp], timeout: 0.1)
    }

    func test_subscribeWithInitialCatch_whenRequestIsNil_shouldNotComplete() {
        let sut = CacheableRequest<Int>(publisherGetter: { nil })

        let exp = XCTestExpectation(description: "Completion not received")
        exp.isInverted = true
        sut.subscribe { _ in }
            .sink(receiveCompletion: { _ in exp.fulfill() },
                  receiveValue: { _ in })
            .store(in: &cancellables)

        wait(for: [exp], timeout: 0.1)
    }

    func test_subscribeWithInitialCatch_whenRequestFails_shouldNotReturnError() {
        var getCount = 0
        let publisherGetter: () -> AnyPublisher<Int, Error> = {
            getCount += 1
            switch getCount {
            case 1: return Fail(error: TestError()).eraseToAnyPublisher()
            case 2: return Just(2).setFailureType(to: Error.self).eraseToAnyPublisher()
            default: XCTFail("Expected two calls to get publisher, but got \(getCount)")
                return Fail(error: TestError()).eraseToAnyPublisher()
            }
        }

        let sut = CacheableRequest(publisherGetter: publisherGetter)
        let initialErrorExp = XCTestExpectation(description: "Initial request failed")
        let exp = sut.subscribe { _ in initialErrorExp.fulfill() }
            .wait(for: TestError())
            .store(in: &cancellables)
        exp.isInverted = true

        wait(for: [initialErrorExp, exp], timeout: 0.1)
    }

    func test_subscribeWithInitialCatch_whenValueWasCachedAndSubscribeCalledForceRefresh_shouldReturnNewValue() {
        var getCount = 0
        let publisherGetter: () -> AnyPublisher<Int, Error> = {
            getCount += 1
            if getCount == 1 {
                return Just(1).setFailureType(to: Error.self).eraseToAnyPublisher()
            } else {
                return Just(2).setFailureType(to: Error.self).eraseToAnyPublisher()
            }
        }

        let sut = CacheableRequest(publisherGetter: publisherGetter)
        sut.get().sink(receiveCompletion: { _ in }, receiveValue: { _ in })
            .store(in: &cancellables)
        let exp = sut.get().wait(for: 1)
            .store(in: &cancellables)
        wait(for: [exp], timeout: 1)

        let exp2 = sut.subscribe(forceRefresh: true) { _ in }
            .wait(for: 2)
            .store(in: &cancellables)
        wait(for: [exp2], timeout: 1)
    }

    func test_subscribeWithInitialCatch_whenRequestFails_shouldNotPassErrorDownstream() {
        var getCount = 0
        let publisherGetter: () -> AnyPublisher<Int, Error> = {
            getCount += 1
            switch getCount {
            case 1: return Fail(error: TestError()).eraseToAnyPublisher()
            case 2: return Just(2).setFailureType(to: Error.self).eraseToAnyPublisher()
            default: XCTFail("Expected two calls to get publisher, but got \(getCount)")
                return Fail(error: TestError()).eraseToAnyPublisher()
            }
        }

        let initialErrorExp = XCTestExpectation(description: "Initial request failed")
        let sut = CacheableRequest(publisherGetter: publisherGetter)
        let exp = sut.subscribe { _ in initialErrorExp.fulfill() }
            .wait(for: TestError())
            .store(in: &cancellables)
        exp.isInverted = true

        wait(for: [initialErrorExp, exp], timeout: 0.1)
    }

    func test_subscribeWithInitialCatch_whenInitialRequestFailsAndValueIsEmittedLater_shouldReturnAndCacheValue() {
        var getCount = 0
        var subscribeCount = 0
        let publisherGetter: () -> AnyPublisher<Int, Error> = {
            getCount += 1
            switch getCount {
            case 1: return Fail(error: TestError()).eraseToAnyPublisher()
            case 2: return Just(2)
                .handleEvents(receiveSubscription: { _ in subscribeCount += 1})
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
            default: XCTFail("Expected two calls to get publisher, but got \(getCount)")
                return Fail(error: TestError()).eraseToAnyPublisher()
            }
        }

        let initialErrorExp = XCTestExpectation(description: "Initial request failed")
        let sut = CacheableRequest(publisherGetter: publisherGetter)
        let exp = sut.subscribe { _ in initialErrorExp.fulfill() }
            .wait(for: 2)
            .store(in: &cancellables)
        let exp2 = sut.get()
            .wait(for: 2)
            .store(in: &cancellables)

        wait(for: [initialErrorExp, exp, exp2], timeout: 1)
        XCTAssertEqual(subscribeCount, 1)
    }

    // swiftlint:disable:next line_length
    func test_subscribeWithInitialCatch_whenInitialRequestFailsWithTwoSubscribersAndValueIsEmittedLater_shouldReturnValueToBothSubscribers() {
        var getCount = 0
        let subject1 = PassthroughSubject<Int, Error>()
        let subject2 = PassthroughSubject<Int, Error>()
        let publisherGetter: () -> AnyPublisher<Int, Error> = {
            getCount += 1
            switch getCount {
            case 1: return subject1.eraseToAnyPublisher()
            case 2: return subject2.eraseToAnyPublisher()
            default: XCTFail("Expected two calls to get publisher, but got \(getCount)")
                return Fail(error: TestError()).eraseToAnyPublisher()
            }
        }

        let initialErrorExp = XCTestExpectation(description: "Initial request failed")
        let initialErrorExp2 = XCTestExpectation(description: "Initial request failed2")
        let sut = CacheableRequest(publisherGetter: publisherGetter)
        let exp = sut.subscribe { _ in initialErrorExp.fulfill() }
            .wait(for: 2)
            .store(in: &cancellables)
        let exp2 = sut.subscribe { _ in initialErrorExp2.fulfill() }
            .wait(for: 2)
            .store(in: &cancellables)
        subject1.send(completion: .failure(TestError()))
        wait(for: [initialErrorExp, initialErrorExp2], timeout: 1)

        let exp3 = sut.get()
            .wait(for: 2)
            .store(in: &cancellables)

        subject2.send(2)
        wait(for: [exp, exp2, exp3], timeout: 1)
    }

    func test_subscribeWithInitialCatch_whenInitialRequestFailsAndNextRequestFails_shouldNotComplete() {
        var getCount = 0
        let publisherGetter: () -> AnyPublisher<Int, Error> = {
            getCount += 1
            switch getCount {
            case 1: return Fail(error: TestError()).eraseToAnyPublisher()
            case 2: return Fail(error: TestError()).eraseToAnyPublisher()
            default: XCTFail("Expected two calls to get publisher, but got \(getCount)")
                return Fail(error: TestError()).eraseToAnyPublisher()
            }
        }

        let notCompletedExp = XCTestExpectation(description: "Subscribtion is completed")
        notCompletedExp.isInverted = true
        let sut = CacheableRequest(publisherGetter: publisherGetter)
        sut.subscribe { _ in }
            .sink(receiveCompletion: { _ in notCompletedExp.fulfill() },
                  receiveValue: { _ in })
            .store(in: &cancellables)
        let errorOnGetExp = sut.get()
            .wait(for: TestError())
            .store(in: &cancellables)

        wait(for: [notCompletedExp, errorOnGetExp], timeout: 0.1)
    }

    func test_subscribeWithInitialCatch_whenRequestTwiceAndThenValueIsEmitted_shouldReceiveValue() {
        var getCount = 0
        let subject1 = PassthroughSubject<Int, Error>()
        let subject2 = PassthroughSubject<Int, Error>()
        let subject3 = PassthroughSubject<Int, Error>()
        let publisherGetter: () -> AnyPublisher<Int, Error> = {
            getCount += 1
            switch getCount {
            case 1: return subject1.eraseToAnyPublisher()
            case 2: return subject2.eraseToAnyPublisher()
            case 3: return subject3.eraseToAnyPublisher()
            default: XCTFail("Expected two calls to get publisher, but got \(getCount)")
                return Fail(error: TestError()).eraseToAnyPublisher()
            }
        }

        let notCompletedExp = XCTestExpectation(description: "Subscribtion is completed")
        notCompletedExp.isInverted = true
        let sut = CacheableRequest(publisherGetter: publisherGetter)

        let initialErrorExp = XCTestExpectation(description: "Initial request failed")

        // first request trigger fail
        let subscribeValueExp = sut.subscribe { _ in initialErrorExp.fulfill() }
            .wait(for: 2)
            .store(in: &cancellables)
        subject1.send(completion: .failure(TestError()))
        wait(for: [initialErrorExp], timeout: 1)

        // second request trigger fail
        let errorOnGetExp = sut.get()
            .wait(for: TestError())
            .store(in: &cancellables)
        subject2.send(completion: .failure(TestError()))
        wait(for: [errorOnGetExp], timeout: 1)

        // third request trigger passes
        let getValueExp = sut.get()
            .wait(for: 2)
            .store(in: &cancellables)
        subject3.send(2)
        wait(for: [getValueExp, subscribeValueExp], timeout: 1)
    }
}
