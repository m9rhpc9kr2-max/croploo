/// Canned CullyAI reply text used by [features/basis/basis_detail_screen.dart]
/// to pre-fill an "Ask CullyAI" prompt. Everything else that used to live
/// here now comes from the real backend (see live_repository.dart) —
/// this is the one UI call site that still reaches into static sample
/// text directly, rather than through the repository interface.
class MockData {
  MockData._();

  static String cullyReply(String prompt) {
    final p = prompt.toLowerCase();
    if (p.contains('corn')) {
      return 'Corn is trading with a bearish tilt after the June WASDE added 45M bu to ending stocks. For basis: interior locations in IL/IN are running 15–25¢ under their 5-year averages — historically that gap closes within 2–3 weeks in 74% of cases. If you\'re an origination desk, ADM Decatur (-22¢ vs avg) is the standout dislocation today.';
    }
    if (p.contains('soy')) {
      return 'Soybeans caught a bid on last week\'s export sales — 1.42M MT net, well above estimates, with China booking 18 cargoes. Gulf basis should firm first, then pull river locations up. CHS Mankato is already +14¢ over its 5-year average; the Eastern Belt hasn\'t moved yet, which is where the opportunity sits.';
    }
    if (p.contains('wheat')) {
      return 'Wheat is the quiet bull: global ending stocks are the tightest since 2007/08 per the latest WASDE. HRW basis in KS is lagging the futures move — Salina and Wichita bids haven\'t adjusted. Watch harvest pressure fade over the next two weeks.';
    }
    if (p.contains('usda') || p.contains('report') || p.contains('wasde')) {
      return 'Latest WASDE headline: Bearish Corn, Neutral Soybeans, Bullish Wheat. Corn ending stocks came in at 2.102B bu, +45M above estimates. The basis read-through: expect corn basis to widen near export facilities in the Eastern Corn Belt, while KS wheat basis should firm on the tight global balance sheet.';
    }
    if (p.contains('basis')) {
      return 'Today\'s biggest dislocations: Bunge Channahon wheat at -31¢ vs the 5-yr average, ADM Decatur corn at -22¢, and CHS Mankato soybeans at +14¢. Deviations beyond ±20% of the seasonal norm have historically mean-reverted within 2 weeks about 3 times out of 4 — the IL corn locations are the cleanest setups.';
    }
    return 'Here\'s the market in one breath: corn soft on big ending stocks and strong crop ratings, soybeans supported by surprise Chinese buying, wheat quietly bullish on the tightest global stocks in 15+ years. The actionable edge today is in basis — IL corn locations are running 15–25¢ under seasonal norms. Ask me about a specific commodity or location for detail.';
  }
}
