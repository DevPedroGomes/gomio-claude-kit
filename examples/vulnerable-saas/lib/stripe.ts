import Stripe from "stripe";

export const stripe = new Stripe(process.env.STRIPE_SECRET_KEY ?? "");

// Credit packs sold at checkout. Prices are Stripe price ids configured in the dashboard.
export const CREDIT_PACKS: Record<string, { priceId: string; credits: number }> = {
  small: { priceId: "price_small_pack", credits: 100 },
  large: { priceId: "price_large_pack", credits: 1000 },
};
