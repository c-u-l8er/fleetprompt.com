import { AlertTriangle, CheckCircle, XCircle } from "lucide-react";
import { Button } from "../components/ui/button";
import { Card, CardContent } from "../components/ui/card";
import { Badge } from "../components/ui/badge";
import { DirectiveStatusBadge } from "../components/StatusBadge";
import { moderationQueue } from "../mockData";
import { formatDistanceToNow } from "date-fns";

export function ModerationQueuePage() {
  return (
    <div className="p-8">
      <div className="max-w-6xl mx-auto">
        <div className="mb-6">
          <h1 className="text-2xl font-semibold">Moderation Queue</h1>
          <p className="text-neutral-500 mt-1">Review flagged content and agent recommendations</p>
        </div>

        <div className="space-y-4">
          {moderationQueue.map((item) => (
            <Card key={item.id} className="border-yellow-200 bg-yellow-50/30">
              <CardContent className="p-6">
                <div className="flex gap-4">
                  <div className="p-2 bg-yellow-100 rounded-full h-10 w-10 flex items-center justify-center">
                    <AlertTriangle className="h-5 w-5 text-yellow-700" />
                  </div>
                  <div className="flex-1">
                    <div className="flex items-center gap-2 mb-2">
                      <span className="font-medium">{item.reason}</span>
                      <Badge variant="outline" className="text-xs capitalize">
                        {item.contentType}
                      </Badge>
                    </div>
                    <p className="text-sm text-neutral-600 mb-3">{item.contentPreview}</p>
                    
                    <div className="flex items-center gap-2 text-xs text-neutral-500 mb-4">
                      <span>Reported by {item.reportedBy}</span>
                      <span>•</span>
                      <span>{formatDistanceToNow(new Date(item.reportedAt), { addSuffix: true })}</span>
                    </div>

                    {/* Signal Trail */}
                    <div className="mb-4">
                      <h4 className="text-xs font-semibold text-neutral-500 uppercase mb-2">Signal Trail</h4>
                      <div className="space-y-2">
                        {item.signals.map((signal) => (
                          <div key={signal.id} className="flex items-center gap-2 text-sm">
                            <Badge variant="outline" className="text-xs">
                              {signal.type}
                            </Badge>
                            <span className="text-neutral-500 text-xs">
                              {formatDistanceToNow(new Date(signal.createdAt), { addSuffix: true })}
                            </span>
                          </div>
                        ))}
                      </div>
                    </div>

                    {/* Prior Directives */}
                    {item.directives.length > 0 && (
                      <div className="mb-4">
                        <h4 className="text-xs font-semibold text-neutral-500 uppercase mb-2">Directives</h4>
                        <div className="space-y-2">
                          {item.directives.map((directive) => (
                            <div key={directive.id} className="flex items-center gap-2">
                              <DirectiveStatusBadge status={directive.status} />
                              <span className="text-sm text-neutral-600">{directive.type}</span>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}

                    <div className="flex items-center gap-2">
                      <Button size="sm" variant="destructive">
                        <XCircle className="h-4 w-4 mr-2" />
                        Recommend Remove
                      </Button>
                      <Button size="sm" variant="outline">
                        Recommend Lock
                      </Button>
                      <Button size="sm" variant="outline">
                        Recommend Escalate
                      </Button>
                      <Button size="sm" variant="ghost">
                        <CheckCircle className="h-4 w-4 mr-2" />
                        Resolve
                      </Button>
                    </div>
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      </div>
    </div>
  );
}
