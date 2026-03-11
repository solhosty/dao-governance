"use client";

import { useMemo } from "react";
import { Area, AreaChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";

type BondingCurveChartProps = {
  basePriceWei: bigint;
  slopeWei: bigint;
};

type ChartPoint = {
  supply: number;
  priceEth: number;
};

export function BondingCurveChart({ basePriceWei, slopeWei }: BondingCurveChartProps) {
  const data = useMemo<ChartPoint[]>(() => {
    const points: ChartPoint[] = [];
    for (let supply = 0; supply <= 100; supply += 5) {
      const priceWei = basePriceWei + slopeWei * BigInt(supply);
      points.push({ supply, priceEth: Number(priceWei) / 1e18 });
    }
    return points;
  }, [basePriceWei, slopeWei]);

  return (
    <div className="h-72 w-full rounded-lg border border-white/40 bg-white/50 p-4 shadow-glass backdrop-blur-md">
      <h3 className="mb-3 text-sm font-medium text-slate-700">Bonding Curve</h3>
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={data}>
          <defs>
            <linearGradient id="curveGradient" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor="#2563eb" stopOpacity={0.45} />
              <stop offset="95%" stopColor="#2563eb" stopOpacity={0.08} />
            </linearGradient>
          </defs>
          <CartesianGrid strokeDasharray="3 3" stroke="#cbd5e1" />
          <XAxis dataKey="supply" tick={{ fill: "#334155", fontSize: 12 }} />
          <YAxis tick={{ fill: "#334155", fontSize: 12 }} />
          <Tooltip />
          <Area
            type="monotone"
            dataKey="priceEth"
            stroke="#1d4ed8"
            strokeWidth={2}
            fill="url(#curveGradient)"
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}
