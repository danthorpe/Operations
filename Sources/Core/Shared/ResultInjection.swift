//
//  ResultInjection.swift
//  Operations
//
//  Created by Daniel Thorpe on 15/12/2015.
//
//

import Foundation

/**
 # Result Injection

 These protocols and extensions allow the injection of result(s) from
 one operation into another.

 Consider a data processing task. Before it can execute, it must have
 the data to process; this data is a *requirement* of the operation.
 Unless this data is literal (i.e. known at compile time) a good
 practice is to "inject" the data into the data-processing task.
 This is called dependency injection, and a text book would say it is
 best to inject the dependency (i.e. data) into the task's constructor.

 However, with Operations, we cannot exactly do this, and so must set
 it on the operation after initialization. Also to avoid the overloaded
 term "dependency" we are going to refer to this data as a requirement.

 In almost all cases the requirement can be the *result* of another
 operation. Even reading data from the disk should be framed in the
 context of an asychonous task suitable for an Operation. Therefore in
 general we wish to take the result from one operation and set it as
 the requirement on another. This implies an operation dependency. The
 data-processing operation depends upon the successful completion of
 the data-retrieval operation.

 In the most general case, we can achieve this by making the
 data-processing operation conform to `InjectionOperationType`.

 ```swift
 class DataProcessing: Operation, InjectionOperationType {
    // etc
 }
 ```

 With the above definition, it is now possible to setup the injection:

 ```swift
 let fetch = DataRetrieval()
 let processing = DataProcessing()
 processing.injectResultFromDependency(fetch) { op, dep, errors in
   if errors.isEmpty {
     op.data = dep.data
   }
   else {
     // Still thinking about this, how should errors be handled?
     op.cancel()
   }
 }
 queue.addOperations(fetch, processing)
 ```

 Note here, that the closure's arguments are generic types, so
 `op` is actually the `processing` operation, and `dep` is the
 `fetch` operation. They are properly typed, and we are assuming that
 each `data` property is set up accordingly.

 The usage of this closure is why we refer to this as manual injection.

 This can be pretty handy if there are many different requirements which
 need setting from the same dependency.

 Additionally - there is no limitation on how many times this is used. If
 an operation has requirements from multiple dependencies - call it for
 each dependency.
*/
public protocol InjectionOperationType: class { }

extension InjectionOperationType where Self: Operation {

    /**
     Access the completed dependency operation before `self` is
     started. This can be useful for transfering results/data between
     operations.

     - parameters dep: any `Operation` subclass.
     - parameters block: a closure which receives `self`, the dependent
     operation, and an array of `ErrorType`, and returns Void.
     - returns: `self` - so that injections can be chained together.
    */
    public func injectResultFromDependency<T where T: Operation>(dep: T, block: (operation: Self, dependency: T, errors: [ErrorType]) -> Void) -> Self {
        dep.addObserver(WillFinishObserver { [weak self] op, errors in
            if let strongSelf = self, dep = op as? T {
                block(operation: strongSelf, dependency: dep, errors: errors)
            }
        })
        dep.addObserver(DidCancelObserver { [weak self] op in
            if let strongSelf = self, _ = op as? T {
                (strongSelf as Operation).cancel()
            }
        })
        (self as Operation).addDependency(dep)
        return self
    }
}

/**
 A protocol which operations must conform to, for their
 "result" to be automatically injected as "requirement" into
 an operation conforming to `AutomaticInjectionOperationType`.
*/
public protocol ResultOperationType: class {
    associatedtype Result

    /// - returns: the `Result`, note that this can be an `Thing?` if needed.
    var result: Result { get }
}

/**
 A protocol which operations must conform to, for "requirement"
 to be injected automatically from the "result" of an operation
 conforming to `ResultOperationType`.
 */
public protocol AutomaticInjectionOperationType: InjectionOperationType {
    associatedtype Requirement

    /// - returns: the `Requirement`, note must be mutable, and
    /// can be `Thing?` if needed.
    var requirement: Requirement { get set }
}

/**
 ErrorType for automatic injection.

 In the case where the dependency operation finishes with an error
 the dependent operaton will be cancelled with a AutomaticInjectionError

 The only case indicates this, and composes the errors the
 dependency finished with.
*/
public enum AutomaticInjectionError: ErrorType {
    case DependencyFinishedWithErrors([ErrorType])
    case RequirementNotSatisfied
}

extension AutomaticInjectionOperationType where Self: Operation {

    /**
     Inject the result from one operation as the requirement of
     another operation. For example consider data retrieval and
     data processing operation classes:

     ```swift
     class DataRetrieval: Operation, ResultOperationType {
        var result: NSData? = .None

        // etc etc
     }

     class DataProcessing: Operation, AutomaticInjectionOperationType {
        var requirement: NSData? = .None

        // etc etc
     }
     ```

     then you can do the following:

     ```swift
     let fetch = DataRetrieval()
     let processing = DataProcessing()
     processing.injectResultFromDependency(fetch)
     queue.addOperations(fetch, processing)
     ```

     - parameter dep: an operation of type T
     - returns: the receiver
    */
    public func injectResultFromDependency<T where T: Operation, T: ResultOperationType, T.Result == Requirement>(dep: T) -> Self {
        return injectResultFromDependency(dep) { [weak self] operation, dependency, errors in
            if errors.isEmpty {
                self?.requirement = dependency.result
            }
            else {
                self?.cancelWithError(AutomaticInjectionError.DependencyFinishedWithErrors(errors))
            }
        }
    }

    /**
     Inject the result from the dependency as the requirement of the receiver.
     Additionally this method requires that the dependency must not fail or be
     cancelled.

    ```swift
     return operation
        .requireResultFromDependency(foo)
        .requireResultFromDependency(bar)
        .requireResultFromDependency(baz)
        .requireResultFromDependency(bat)
     ```

     - parameter dep: an operation of type T
     - returns: the receiver
    */
    public func requireResultFromDependency<T where T: Operation, T: ResultOperationType, T.Result == Requirement>(dep: T) -> Self {
        if conditions.filter({ return $0 is NoFailedDependenciesCondition }).count < 1 {
            addCondition(NoFailedDependenciesCondition())
        }
        return injectResultFromDependency(dep)
    }
}


/// Protocol for non-Operation types to conform to yet enjoy scheduling in Operation
public protocol Executor: ResultOperationType, AutomaticInjectionOperationType {

    /**
     Will be called to execute the _work_. When the work is finished, the
     finish block should be invoked. If any errors were encounted pass
     them into the finish block. If the work produces a result, the value
     should be made available at the `result` property before invoking the
     finish block.

     - parameter finish: a closure which receives an ErrorType?
    */
    func execute(finish: ErrorType? -> Void)

    /// Will be called to signal that the _work_ should be cancelled.
    func cancel()
}

/**
 Execute is an Operation which is intended to compose other types which _perform work_. These
 types must conform to Executor protocol, and essentially expose API to trigger execution of
 the work, support cancellation, and extend protocols for result injection.

 Execute is initialized with an instance of such a class. When the operation is ready, it will
 call execute on the Executor, and catch any thrown errors. If the operation is cancelled, it
 will call cancel on the executor.
 */
public final class Execute<E: Executor>: Operation, ResultOperationType, AutomaticInjectionOperationType {

    /// - returns: executor, the instance of the Executor
    public let executor: E

    /// - returns: the Executor.Result
    public var result: E.Result {
        return executor.result
    }

    /// - returns: the Executor.Requirement
    public var requirement: E.Requirement {
        get { return executor.requirement }
        set { executor.requirement = newValue }
    }

    /**
     Initialize the operation with the executor.

     - parametere [unnamed]: an instance of Executor
    */
    public init(_ executor: E) {
        self.executor = executor
        super.init()
        addObserver(DidCancelObserver { [unowned self] operation in
            if self === operation {
                self.executor.cancel()
            }
        })
    }

    public final override func execute() {
        executor.execute(finish)
    }
}
