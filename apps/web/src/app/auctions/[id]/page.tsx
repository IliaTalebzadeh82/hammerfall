import { notFound } from "next/navigation";
import { AuctionDetail } from "@/components/auction/auction-detail";
export default async function AuctionPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  if (!/^[1-9]\d*$/.test(id) || !Number.isSafeInteger(Number(id))) notFound();
  return <AuctionDetail key={id} id={Number(id)} />;
}
