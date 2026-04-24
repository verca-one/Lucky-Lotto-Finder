import dynamic from "next/dynamic";

interface SimpleMapProps {
  lat: number;
  lng: number;
  zoom?: number;
  onMarkerClick?: () => void;
}

const SimpleMapClient = dynamic(
  () => import("./SimpleMapClient"),
  { ssr: false }
);

export default function SimpleMap(props: SimpleMapProps) {
  return <SimpleMapClient {...props} />;
}
