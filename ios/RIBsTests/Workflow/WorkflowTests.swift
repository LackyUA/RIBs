//
//  Copyright (c) 2017. Uber Technologies
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import XCTest
import Combine
@testable import RIBs

final class WorkerflowTests: XCTestCase {

    func test_nestedStepsDoNotRepeat() {
        var outerStep1RunCount = 0
        var outerStep2RunCount = 0
        var outerStep3RunCount = 0

        var innerStep1RunCount = 0
        var innerStep2RunCount = 0
        var innerStep3RunCount = 0

        let emptyObservable = Just(((), ())).setFailureType(to: Error.self).eraseToAnyPublisher()

        let workflow = Workflow<String, Error>()
        _ = workflow
            .onStep { (mock) -> AnyPublisher<((), ()), Error> in
                outerStep1RunCount += 1

                return emptyObservable.eraseToAnyPublisher()
            }
            .onStep { (_, _) -> AnyPublisher<((), ()), Error> in
                outerStep2RunCount += 1

                return emptyObservable.eraseToAnyPublisher()
            }
            .onStep { (_, _) -> AnyPublisher<((), ()), Error> in
                outerStep3RunCount += 1

                let innerStep: Step<String, (), (), Error>? = emptyObservable.fork(workflow)

                innerStep?
                    .onStep({ (_, _) -> AnyPublisher<((), ()), Error> in
                        innerStep1RunCount += 1
                        return emptyObservable
                    })
                    .onStep({ (_, _) -> AnyPublisher<((), ()), Error> in
                        innerStep2RunCount += 1
                        return emptyObservable
                    })
                    .onStep({ (_, _) -> AnyPublisher<((), ()), Error> in
                        innerStep3RunCount += 1
                        return emptyObservable
                    })
                    .commit()

                return emptyObservable.eraseToAnyPublisher()
            }
            .commit()
            .subscribe("Test Actionable Item")

        XCTAssertEqual(outerStep1RunCount, 1, "Outer step 1 should not have been run more than once")
        XCTAssertEqual(outerStep2RunCount, 1, "Outer step 2 should not have been run more than once")
        XCTAssertEqual(outerStep3RunCount, 1, "Outer step 3 should not have been run more than once")

        XCTAssertEqual(innerStep1RunCount, 1, "Inner step 1 should not have been run more than once")
        XCTAssertEqual(innerStep2RunCount, 1, "Inner step 2 should not have been run more than once")
        XCTAssertEqual(innerStep3RunCount, 1, "Inner step 3 should not have been run more than once")
    }

    func test_workflowReceivesError() {
        let workflow = TestWorkflow()

        let emptyObservable = Just(((), ())).setFailureType(to: WorkflowTestError.self).eraseToAnyPublisher()
        _ = workflow
            .onStep { _ -> AnyPublisher<((), ()), WorkflowTestError> in
                return emptyObservable
            }
            .onStep { _, _ -> AnyPublisher<((), ()), WorkflowTestError> in
                return emptyObservable
            }
            .onStep { _, _ -> AnyPublisher<((), ()), WorkflowTestError> in
                return Fail(error: WorkflowTestError.error).eraseToAnyPublisher()
            }
            .onStep { _, _ -> AnyPublisher<((), ()), WorkflowTestError> in
                return emptyObservable
            }
            .commit()
            .subscribe(())

        XCTAssertEqual(0, workflow.completeCallCount)
        XCTAssertEqual(0, workflow.forkCallCount)
        XCTAssertEqual(1, workflow.errorCallCount)
    }

    func test_workflowDidComplete() {
        let workflow = TestWorkflow()

        let emptyObservable = Just(((), ())).setFailureType(to: WorkflowTestError.self).eraseToAnyPublisher()
        _ = workflow
            .onStep { _ -> AnyPublisher<((), ()), WorkflowTestError> in
                return emptyObservable
            }
            .onStep { _, _ -> AnyPublisher<((), ()), WorkflowTestError> in
                return emptyObservable
            }
            .onStep { _, _ -> AnyPublisher<((), ()), WorkflowTestError> in
                return emptyObservable
            }
            .commit()
            .subscribe(())

        XCTAssertEqual(1, workflow.completeCallCount)
        XCTAssertEqual(0, workflow.forkCallCount)
        XCTAssertEqual(0, workflow.errorCallCount)
    }

    func test_workflowDidFork() {
        let workflow = TestWorkflow()

        let emptyObservable = Just(((), ())).setFailureType(to: WorkflowTestError.self).eraseToAnyPublisher()
        _ = workflow
            .onStep { _ -> AnyPublisher<((), ()), WorkflowTestError> in
                return emptyObservable
            }
            .onStep { _, _ -> AnyPublisher<((), ()), WorkflowTestError> in
                return emptyObservable
            }
            .onStep { _, _ -> AnyPublisher<((), ()), WorkflowTestError> in
                return emptyObservable
            }
            .onStep { _, _ -> AnyPublisher<((), ()), WorkflowTestError> in
                let forkedStep: Step<(), (), (), WorkflowTestError>? = emptyObservable.fork(workflow)
                forkedStep?
                    .onStep { _, _ -> AnyPublisher<((), ()), WorkflowTestError> in
                        return emptyObservable
                    }
                    .commit()
                return emptyObservable
            }
            .commit()
            .subscribe(())

        XCTAssertEqual(1, workflow.completeCallCount)
        XCTAssertEqual(1, workflow.forkCallCount)
        XCTAssertEqual(0, workflow.errorCallCount)
    }

    func test_fork_verifySingleInvocationAtRoot() {
        let workflow = TestWorkflow()

        var rootCallCount = 0
        let emptyObservable = Just(((), ())).setFailureType(to: WorkflowTestError.self).eraseToAnyPublisher()
        let rootStep = workflow
            .onStep { _ -> AnyPublisher<((), ()), WorkflowTestError> in
                rootCallCount += 1
                return emptyObservable
        }

        let firstFork: Step<(), (), (), WorkflowTestError>? = rootStep.asPublisher().fork(workflow)
        _ = firstFork?
            .onStep { (_, _) -> AnyPublisher<((), ()), WorkflowTestError> in
                return Just(((), ())).setFailureType(to: WorkflowTestError.self).eraseToAnyPublisher()
            }
            .commit()

        let secondFork: Step<(), (), (), WorkflowTestError>? = rootStep.asPublisher().fork(workflow)
        _ = secondFork?
            .onStep { (_, _) -> AnyPublisher<((), ()), WorkflowTestError> in
                return Just(((), ())).setFailureType(to: WorkflowTestError.self).eraseToAnyPublisher()
            }
            .commit()

        XCTAssertEqual(0, rootCallCount)

        _ = workflow.subscribe(())

        XCTAssertEqual(1, rootCallCount)
    }
}

private enum WorkflowTestError: Error {
    case error
}

private class TestWorkflow: Workflow<(), WorkflowTestError> {
    var completeCallCount = 0
    var errorCallCount = 0
    var forkCallCount = 0

    override func didComplete() {
        completeCallCount += 1
    }

    override func didFork() {
        forkCallCount += 1
    }

    override func didReceiveError(_ error: WorkflowTestError) {
        errorCallCount += 1
    }
}
