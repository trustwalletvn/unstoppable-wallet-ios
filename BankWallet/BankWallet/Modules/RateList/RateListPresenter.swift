import Foundation
import XRatesKit
import CurrencyKit

class RateListPresenter {
    weak var view: IRateListView?

    private let interactor: IRateListInteractor
    private let router: IRateListRouter
    private let rateListSorter: IRateListSorter
    private let factory: IRateListFactory

    private var coins = [Coin]()
    private let currency: Currency

    init(interactor: IRateListInteractor, router: IRateListRouter, rateListSorter: IRateListSorter, factory: IRateListFactory) {
        self.interactor = interactor
        self.router = router
        self.rateListSorter = rateListSorter
        self.factory = factory

        currency = interactor.currency
    }

}

extension RateListPresenter: IRateListViewDelegate {

    func viewDidLoad() {
        coins = rateListSorter.smartSort(for: interactor.wallets.map { $0.coin }, featuredCoins: interactor.featuredCoins)

        var marketInfos = [CoinCode: MarketInfo]()
        coins.forEach { coin in
            marketInfos[coin.code] = interactor.marketInfo(coinCode: coin.code, currencyCode: currency.code)
        }

        let item = factory.rateListViewItem(coins: coins, currency: currency, marketInfos: marketInfos)
        view?.show(item: item)

        let topMarketInfos = interactor.topMarketInfos(currencyCode: currency.code)
        let topRateViewItems = topMarketInfos.map { factory.topRateViewItem(currency: currency, topMarketInfo: $0) }
        view?.show(topRateViewItems: topRateViewItems)

        interactor.subscribeToMarketInfos(currencyCode: currency.code)
        interactor.subscribeToMarketInfos()
    }

    func onSelect(coinCode: String, coinTitle: String, diff: Decimal?) {
        guard diff != nil else {
            return
        }

        router.showChart(coinCode: coinCode, coinTitle: coinTitle)
    }

}

extension RateListPresenter: IRateListInteractorDelegate {

    func didReceive(marketInfos: [String: MarketInfo]) {
        let item = factory.rateListViewItem(coins: coins, currency: currency, marketInfos: marketInfos)
        view?.show(item: item)
    }

    func didReceive(topMarketInfos: [MarketInfo]) {
        let topRateViewItems = topMarketInfos.map { factory.topRateViewItem(currency: currency, topMarketInfo: $0) }
        view?.show(topRateViewItems: topRateViewItems)
    }

}
