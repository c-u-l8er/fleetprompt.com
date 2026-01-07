import { Card, CardContent } from "../components/ui/card";
import { LucideIcon } from "lucide-react";

interface PlaceholderPageProps {
  title: string;
  description: string;
  icon: LucideIcon;
}

export function PlaceholderPage({ title, description, icon: Icon }: PlaceholderPageProps) {
  return (
    <div className="p-8">
      <div className="max-w-4xl mx-auto">
        <div className="mb-6">
          <h1 className="text-2xl font-semibold">{title}</h1>
          <p className="text-neutral-500 mt-1">{description}</p>
        </div>

        <Card>
          <CardContent className="p-12 text-center">
            <Icon className="h-12 w-12 text-neutral-400 mx-auto mb-4" />
            <h3 className="text-lg font-semibold mb-2">Coming Soon</h3>
            <p className="text-neutral-500">This page is under construction</p>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
