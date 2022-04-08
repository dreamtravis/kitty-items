// Use full class names to avoid auto-purging https://tailwindcss.com/docs/optimizing-for-production#writing-purgeable-html
export function itemGradientClass(rarity) {
  switch (String(rarity)) {
    case "0":
      return "item-gradient-3"
    case "1":
      return "item-gradient-2"
    case "2":
      return "item-gradient-1"
    case "gray":
      return "item-gradient-gray"
    default:
      return "item-gradient-gray"
  }
}

export function rarityTextColors(rarity) {
  switch (String(rarity)) {
    case "0":
      return "text-gold"
    case "1":
      return "text-purple"
    case "2":
      return "text-blue"
    default:
      return "text-blue"
  }
}
