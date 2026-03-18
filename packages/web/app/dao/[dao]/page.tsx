"use client";

import { useEffect, useMemo, useState } from "react";
import type { GetLogsReturnType } from "viem";
import { getAbiItem, getAddress } from "viem";
import { usePublicClient, useReadContract, useWriteContract } from "wagmi";

import { CreateProposalModal } from "@/components/dao/create-proposal-modal";
import { Breadcrumbs } from "@/components/navigation/breadcrumbs";
import { EmptyState } from "@/components/ui/empty-state";
import { daoAbi } from "@/lib/abi/dao";
import { daoFactoryAbi } from "@/lib/abi/daoFactory";
import { DAO_FACTORY_ADDRESS } from "@/lib/contracts";

type DAOPageProps = {
  params: {
    dao: string;
  };
};

const MAX_LOG_BLOCK_RANGE = 10_000n;
const MIN_LOG_BLOCK_RANGE = 625n;
const RECENT_LOG_LOOKBACK = 120_000n;

function isBlockRangeLimitError(error: unknown): boolean {
  if (!(error instanceof Error)) {
    return false;
  }

  const message = error.message.toLowerCase();

  return (
    message.includes("block range") ||
    message.includes("max range") ||
    message.includes("range limit") ||
    message.includes("query exceeds") ||
    message.includes("response size exceeded") ||
    message.includes("limited to") ||
    message.includes("try with this block range")
  );
}

function getProposalFeedErrorMessage(error: unknown): string {
  if (isBlockRangeLimitError(error)) {
    return "Recent proposal history is unavailable on this RPC endpoint due to Sepolia block-range limits. You can still enter a proposal ID manually, or switch to a higher-capacity RPC to load the feed.";
  }

  return "Proposal feed is temporarily unavailable. You can still enter a proposal ID manually and vote.";
}

export default function DaoDetailPage({ params }: DAOPageProps) {
  const [proposalId, setProposalId] = useState("");
  const [proposalFeed, setProposalFeed] = useState<
    Array<{
      proposalId: bigint;
      proposer: `0x${string}`;
      description: string;
      voteStart: bigint;
      voteEnd: bigint;
      blockNumber: bigint;
    }>
  >([]);
  const [proposalStates, setProposalStates] = useState<Record<string, bigint>>({});
  const [proposalLoadError, setProposalLoadError] = useState<string | null>(null);

  const publicClient = usePublicClient();

  const parsedDaoId = useMemo(() => {
    const match = /^(\d+)(?:[-_].*)?$/.exec(params.dao);
    if (match?.[1]) {
      return BigInt(match[1]);
    }
    return undefined;
  }, [params.dao]);

  const parsedDaoAddress = useMemo(() => {
    try {
      return getAddress(params.dao);
    } catch {
      return undefined;
    }
  }, [params.dao]);

  const { data: infoById } = useReadContract({
    abi: daoFactoryAbi,
    address: DAO_FACTORY_ADDRESS,
    functionName: "getDAO",
    args: parsedDaoId !== undefined ? [parsedDaoId] : undefined,
    query: { enabled: Boolean(DAO_FACTORY_ADDRESS && parsedDaoId !== undefined) },
  });

  const { data: totalDaos } = useReadContract({
    abi: daoFactoryAbi,
    address: DAO_FACTORY_ADDRESS,
    functionName: "totalDAOs",
    query: { enabled: Boolean(DAO_FACTORY_ADDRESS) },
  });

  const { data: listedDaos } = useReadContract({
    abi: daoFactoryAbi,
    address: DAO_FACTORY_ADDRESS,
    functionName: "listDAOs",
    args: totalDaos !== undefined ? [0n, totalDaos] : undefined,
    query: {
      enabled: Boolean(DAO_FACTORY_ADDRESS && totalDaos !== undefined && totalDaos > 0n),
    },
  });

  const resolvedInfo = useMemo(() => {
    if (infoById) {
      return infoById;
    }

    if (!parsedDaoAddress || !listedDaos) {
      return undefined;
    }

    return listedDaos.find((item) => {
      try {
        return getAddress(item.dao) === parsedDaoAddress;
      } catch {
        return false;
      }
    });
  }, [infoById, listedDaos, parsedDaoAddress]);

  const daoAddress = useMemo(() => {
    if (resolvedInfo?.dao) {
      return getAddress(resolvedInfo.dao);
    }

    return parsedDaoAddress;
  }, [parsedDaoAddress, resolvedInfo?.dao]);

  useEffect(() => {
    let cancelled = false;

    async function loadProposalFeed() {
      if (!publicClient || !daoAddress) {
        if (!cancelled) {
          setProposalFeed([]);
          setProposalLoadError(null);
        }
        return;
      }

      try {
        const latestBlock = await publicClient.getBlockNumber();
        const fromBlockWindow =
          latestBlock > RECENT_LOG_LOOKBACK ? latestBlock - RECENT_LOG_LOOKBACK + 1n : 0n;

        const proposalCreatedEvent = getAbiItem({ abi: daoAbi, name: "ProposalCreated" });
        const logs: GetLogsReturnType<typeof proposalCreatedEvent> = [];

        let toBlock = latestBlock;
        let rangeSize = MAX_LOG_BLOCK_RANGE;
        let partialError: unknown = null;

        while (toBlock >= fromBlockWindow) {
          const fromBlockCandidate =
            toBlock > fromBlockWindow + rangeSize - 1n ? toBlock - rangeSize + 1n : fromBlockWindow;

          try {
            const chunkLogs = await publicClient.getLogs({
              address: daoAddress,
              event: proposalCreatedEvent,
              fromBlock: fromBlockCandidate,
              toBlock,
            });

            logs.push(...chunkLogs);

            if (fromBlockCandidate === fromBlockWindow) {
              break;
            }

            toBlock = fromBlockCandidate - 1n;
          } catch (error) {
            if (isBlockRangeLimitError(error) && rangeSize > MIN_LOG_BLOCK_RANGE) {
              rangeSize = rangeSize / 2n;
              continue;
            }

            partialError = error;
            break;
          }
        }

        if (cancelled) {
          return;
        }

        const feed = logs
          .map((log) => {
            const args = log.args;

            if (
              args.proposalId === undefined ||
              args.proposer === undefined ||
              args.description === undefined ||
              args.voteStart === undefined ||
              args.voteEnd === undefined ||
              log.blockNumber === null
            ) {
              return null;
            }

            return {
              proposalId: args.proposalId,
              proposer: args.proposer,
              description: args.description,
              voteStart: args.voteStart,
              voteEnd: args.voteEnd,
              blockNumber: log.blockNumber,
            };
          })
          .filter((entry) => entry !== null)
          .sort((a, b) => Number(b.blockNumber - a.blockNumber));

        setProposalFeed(feed);
        setProposalLoadError(partialError ? getProposalFeedErrorMessage(partialError) : null);

        if (feed.length === 0 && partialError) {
          setProposalFeed([]);
        }
      } catch (error) {
        if (!cancelled) {
          setProposalFeed([]);
          setProposalLoadError(getProposalFeedErrorMessage(error));
        }
      }
    }

    void loadProposalFeed();

    return () => {
      cancelled = true;
    };
  }, [daoAddress, publicClient]);

  useEffect(() => {
    let cancelled = false;

    async function loadProposalStates() {
      if (!publicClient || !daoAddress || proposalFeed.length === 0) {
        if (!cancelled) {
          setProposalStates({});
        }
        return;
      }

      const entries = await Promise.all(
        proposalFeed.map(async (proposal) => {
          try {
            const state = await publicClient.readContract({
              abi: daoAbi,
              address: daoAddress,
              functionName: "state",
              args: [proposal.proposalId],
            });

            return [proposal.proposalId.toString(), state] as const;
          } catch {
            return [proposal.proposalId.toString(), 0n] as const;
          }
        }),
      );

      if (!cancelled) {
        setProposalStates(Object.fromEntries(entries));
      }
    }

    void loadProposalStates();

    return () => {
      cancelled = true;
    };
  }, [daoAddress, proposalFeed, publicClient]);

  const parsedProposalId = useMemo(() => {
    if (/^\d+$/.test(proposalId)) {
      return BigInt(proposalId);
    }
    return undefined;
  }, [proposalId]);

  const { data: state } = useReadContract({
    abi: daoAbi,
    address: daoAddress,
    functionName: "state",
    args: parsedProposalId !== undefined ? [parsedProposalId] : undefined,
    query: { enabled: Boolean(daoAddress && parsedProposalId !== undefined) },
  });

  const { writeContract, isPending } = useWriteContract();

  const daoLabel = resolvedInfo
    ? `${resolvedInfo.name} (${resolvedInfo.symbol})`
    : parsedDaoId !== undefined
      ? `DAO #${parsedDaoId.toString()}`
      : "DAO detail";

  const marketAddress = resolvedInfo ? getAddress(resolvedInfo.market) : undefined;

  const selectedProposal = useMemo(() => {
    if (parsedProposalId === undefined) {
      return undefined;
    }

    return proposalFeed.find((item) => item.proposalId === parsedProposalId);
  }, [parsedProposalId, proposalFeed]);

  const selectedState =
    parsedProposalId === undefined ? undefined : proposalStates[parsedProposalId.toString()] ?? state;

  if (!daoAddress) {
    return (
      <main className="space-y-4">
        <Breadcrumbs
          items={[
            { label: "Home", href: "/" },
            { label: "My DAOs", href: "/my-daos" },
            { label: "DAO detail" },
          ]}
          backHref="/my-daos"
          backLabel="Back to My DAOs"
        />
        <EmptyState
          title="DAO not found"
          description="Provide a DAO address or numeric ID to continue."
          cta={{ href: "/my-daos", label: "Open My DAOs" }}
          secondaryCta={{ href: "/tokens", label: "Browse token markets" }}
        />
      </main>
    );
  }

  return (
    <main className="space-y-4">
      <Breadcrumbs
        items={[
          { label: "Home", href: "/" },
          { label: "My DAOs", href: "/my-daos" },
          { label: daoLabel },
        ]}
        backHref="/my-daos"
        backLabel="Back to My DAOs"
      />
      <h2 className="text-2xl font-semibold">{daoLabel}</h2>

      <section className="grid gap-2 rounded-lg border border-white/40 bg-white/60 p-4 text-xs shadow-glass backdrop-blur-md md:grid-cols-2">
        <p>
          <span className="font-semibold">DAO address:</span> {daoAddress}
        </p>
        <p>
          <span className="font-semibold">DAO id:</span> {resolvedInfo ? resolvedInfo.id.toString() : "unresolved"}
        </p>
        <p>
          <span className="font-semibold">Token:</span> {resolvedInfo ? `${resolvedInfo.tokenName} (${resolvedInfo.symbol})` : "unresolved"}
        </p>
        <p>
          <span className="font-semibold">Market:</span> {marketAddress ?? "unresolved"}
        </p>
      </section>

      {marketAddress ? (
        <CreateProposalModal daoAddress={daoAddress} marketAddress={marketAddress} />
      ) : null}

      <section className="rounded-lg border border-white/40 bg-white/60 p-4 shadow-glass backdrop-blur-md">
        <h3 className="mb-3 text-lg font-semibold">Vote on Proposal</h3>
        <div className="grid gap-3">
          {proposalFeed.length > 0 ? (
            <select
              className="rounded-md border border-slate-300 bg-white px-3 py-2 text-sm"
              value={proposalId}
              onChange={(event) => setProposalId(event.target.value)}
            >
              <option value="">Select discovered proposal</option>
              {proposalFeed.map((proposal) => {
                const value = proposal.proposalId.toString();
                const currentState = proposalStates[value];
                return (
                  <option key={value} value={value}>
                    #{value} - {proposal.description || "Untitled proposal"} (state {String(currentState ?? "-")})
                  </option>
                );
              })}
            </select>
          ) : null}
          <input
            className="rounded-md border border-slate-300 bg-white px-3 py-2 text-sm"
            value={proposalId}
            onChange={(event) => setProposalId(event.target.value)}
            placeholder="Proposal ID (manual fallback)"
          />
          {proposalLoadError ? (
            <p className="text-xs text-amber-700">{proposalLoadError}</p>
          ) : null}
          {!proposalLoadError && proposalFeed.length === 0 ? (
            <p className="text-xs text-slate-500">
              No recent proposals were found in the latest Sepolia blocks. Enter a proposal ID manually to continue.
            </p>
          ) : null}
          {parsedProposalId === undefined ? (
            <EmptyState
              title="No proposal selected"
              description="Select a discovered proposal or enter an ID manually to view status and cast a vote."
              {...(marketAddress
                ? { cta: { href: `/tokens/${marketAddress}`, label: "Open market" } }
                : {})}
            />
          ) : (
            <>
              <p className="text-xs text-slate-500">
                Current proposal state: {String(selectedState ?? "no proposal activity yet")}
              </p>
              {selectedProposal ? (
                <>
                  <p className="text-xs text-slate-500">Proposer: {selectedProposal.proposer}</p>
                  <p className="text-xs text-slate-500">Voting start: {selectedProposal.voteStart.toString()}</p>
                  <p className="text-xs text-slate-500">Voting end: {selectedProposal.voteEnd.toString()}</p>
                </>
              ) : null}
              <button
                className="rounded-md bg-slate-900 px-4 py-2 text-sm text-white disabled:opacity-60"
                disabled={isPending}
                onClick={() => {
                  writeContract({
                    abi: daoAbi,
                    address: daoAddress,
                    functionName: "castVote",
                    args: [parsedProposalId, 1],
                  });
                }}
              >
                Cast For Vote
              </button>
            </>
          )}
        </div>
      </section>
    </main>
  );
}
