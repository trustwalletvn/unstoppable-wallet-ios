import UIKit
import BigInt
import EthereumKit
import RxSwift
import RxCocoa
import ThemeKit

struct EvmFeeModule {

    static func viewController(feeViewModel: EvmFeeViewModel) -> UIViewController? {
        let feeService = feeViewModel.service
        let coinService = feeViewModel.coinService
        let gasPriceService = feeViewModel.gasPriceService
        let feeViewItemFactory = FeeViewItemFactory(scale: .gwei)
        let cautionsFactory = SendEvmCautionsFactory()

        switch gasPriceService {
        case let legacyService as LegacyGasPriceService:
            let viewModel = LegacyEvmFeeViewModel(gasPriceService: legacyService, feeService: feeService, coinService: coinService, feeViewItemFactory: feeViewItemFactory, cautionsFactory: cautionsFactory)
            return ThemeNavigationController(rootViewController: LegacyEvmFeeViewController(viewModel: viewModel))

        case let eip1559Service as Eip1559GasPriceService:
            let viewModel = Eip1559EvmFeeViewModel(gasPriceService: eip1559Service, feeService: feeService, coinService: coinService, feeViewItemFactory: feeViewItemFactory, cautionsFactory: cautionsFactory)
            return ThemeNavigationController(rootViewController: Eip1559EvmFeeViewController(viewModel: viewModel))

        default: return nil
        }
    }

    static func gasPriceService(evmKit: EthereumKit.Kit, gasPrice: GasPrice? = nil, previousTransaction: EthereumKit.Transaction? = nil) -> IGasPriceService {
        if evmKit.chain.isEIP1559Supported {
            var initialMaxBaseFee: Int? = nil
            var initialMaxTips: Int? = nil
            var minRecommendedBaseFee: Int? = nil
            var minRecommendedTips: Int? = nil

            if case .eip1559(let maxBaseFee, let maxTips) = gasPrice {
                initialMaxBaseFee = maxBaseFee
                initialMaxTips = maxTips
            }

            if let previousMaxFeePerGas = previousTransaction?.maxFeePerGas, let previousMaxPriorityFeePerGas = previousTransaction?.maxPriorityFeePerGas {
                minRecommendedBaseFee = previousMaxFeePerGas - previousMaxPriorityFeePerGas
                minRecommendedTips = previousMaxPriorityFeePerGas
            }

            return Eip1559GasPriceService(evmKit: evmKit, initialMaxBaseFee: initialMaxBaseFee, initialMaxTips: initialMaxTips, minRecommendedBaseFee: minRecommendedBaseFee, minRecommendedTips: minRecommendedTips)
        } else {
            var initialGasPrice: Int? = nil
            var minRecommendedGasPrice: Int? = nil

            if case .legacy(let gasPrice) = gasPrice {
                initialGasPrice = gasPrice
            }

            if let previousGasPrice = previousTransaction?.gasPrice {
                minRecommendedGasPrice = previousGasPrice
            }

            return LegacyGasPriceService(evmKit: evmKit, initialGasPrice: initialGasPrice, minRecommendedGasPrice: minRecommendedGasPrice)
        }
    }
}

extension EvmFeeModule {

    enum GasDataError: Error {
        case insufficientBalance
        case lowMaxFee
    }

    enum GasDataWarning: Warning {
        case riskOfGettingStuck
        case overpricing
    }

    enum GasData {
        case common(gasLimit: Int, gasPrice: GasPrice)
        case rollup(gasLimit: Int, gasPrice: GasPrice, l1Fee: BigUInt)

        var gasLimit: Int {
            switch self {
            case .common(let gasLimit, _): return gasLimit
            case .rollup(let gasLimit, _, _): return gasLimit
            }
        }

        var gasPrice: GasPrice {
            switch self {
            case .common(_, let gasPrice): return gasPrice
            case .rollup(_, let gasPrice, _): return gasPrice
            }
        }

        var fee: BigUInt {
            switch self {
            case .common(let gasLimit, let gasPrice): return BigUInt(gasLimit * gasPrice.max)
            case .rollup(let gasLimit, let gasPrice, let l1Fee): return BigUInt(gasLimit * gasPrice.max) + l1Fee
            }
        }

        var description: String {
            switch self {
            case .common(let gasLimit, let gasPrice): return "L1 transaction: gasLimit:\(gasLimit) - gasPrice:\(gasPrice.description)"
            case .rollup(let gasLimit, let gasPrice, let l1Fee): return "L2 transaction: gasLimit:\(gasLimit) - gasPrice:\(gasPrice.description) - l1fee:\(l1Fee.description)"
            }
        }
    }

    struct Transaction {
        let transactionData: TransactionData
        let gasData: GasData

        var totalAmount: BigUInt {
            transactionData.value + gasData.fee
        }
    }

}

protocol IEvmFeeService {
    var status: DataStatus<FallibleData<EvmFeeModule.Transaction>> { get }
    var statusObservable: Observable<DataStatus<FallibleData<EvmFeeModule.Transaction>>> { get }
}

protocol IGasPriceService {
    var status: DataStatus<FallibleData<GasPrice>> { get }
    var statusObservable: Observable<DataStatus<FallibleData<GasPrice>>> { get }
    var usingRecommended: Bool { get }
}

struct RangeBounds {
    enum BoundType {
        case factor(Float)
        case distance(Int)
        case fixed(Int)
    }

    let lower: BoundType
    let upper: BoundType

    init(lower: BoundType, upper: BoundType) {
        self.lower = lower
        self.upper = upper
    }

    func range(around center: Int, containing selected: Int? = nil) -> ClosedRange<Int> {
        var lowerBound = 0
        var upperBound = 0

        switch lower {
        case .factor(let factor): lowerBound = Int(Float(center) * factor)
        case .distance(let distance): lowerBound = center - distance
        case .fixed(let value): lowerBound = value
        }

        lowerBound = max(lowerBound, 0)

        switch upper {
        case .factor(let factor): upperBound = Int(Float(center) * factor)
        case .distance(let distance): upperBound = center + distance
        case .fixed(let value): upperBound = value
        }

        if let selected = selected {
            lowerBound = min(lowerBound, selected)
            upperBound = max(upperBound, selected)
        }

        return lowerBound...upperBound
    }

}
