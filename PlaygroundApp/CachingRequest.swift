import Foundation
import Combine

@propertyWrapper
public final class CacheableRequest<T> {
    private enum State {
        case notStarted
        case inProgress(publisher: AnyPublisher<T, Error>)
        case done(value: T)
    }

    private var state: State = .notStarted

    private var cancellables = [AnyCancellable]()
    private let publisherGetter: () -> AnyPublisher<T, Error>?
    private var subject = PassthroughSubject<T, Error>()

    public init(publisherGetter: @escaping () -> AnyPublisher<T, Error>?) {
        self.publisherGetter = publisherGetter
    }

    public var wrappedValue: AnyPublisher<T, Error> {
        self.get()
    }

    public func get(forceRefresh: Bool = false) -> AnyPublisher<T, Error> {
        switch state {
        case .done(let value) where !forceRefresh:
            return Just(value).setFailureType(to: Error.self).eraseToAnyPublisher()
        case .inProgress(let publisher):
            return publisher
        default:
            return startRequest()
        }
    }

    public func subscribe(forceRefresh: Bool = false) -> AnyPublisher<T, Error> {
        subject
            .prepend(get(forceRefresh: forceRefresh))
            .eraseToAnyPublisher()
    }

    public func subscribe(forceRefresh: Bool = false, initialCatch: @escaping (Error) -> ()) -> AnyPublisher<T, Error> {
        subject
            .prepend(
                get(forceRefresh: forceRefresh)
                    .catch { error -> Empty<T, Error> in
                        initialCatch(error)
                        return Empty<T, Error>(completeImmediately: true)
                    }
                    .eraseToAnyPublisher()
            )
            .eraseToAnyPublisher()
    }

    private func startRequest() -> AnyPublisher<T, Error> {
        let publisher = ( publisherGetter() ?? { Empty<T, Error>().eraseToAnyPublisher() }()).share().eraseToAnyPublisher()
        state = .inProgress(publisher: publisher)
        return publisher
            .handleEvents(
                receiveOutput: { [weak self] output in
                    self?.state = .done(value: output)
                    self?.subject.send(output)
                },
                receiveCompletion: { [weak self] completion in
                    switch completion {
                    case .failure:
                        self?.state = .notStarted
                    case .finished:
                        break
                    }
                }
            )
            .eraseToAnyPublisher()
    }
}
