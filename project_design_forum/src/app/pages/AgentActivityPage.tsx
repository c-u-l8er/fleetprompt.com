import { Activity, Sparkles, FileText, Flag, BarChart } from "lucide-react";
import { Card, CardContent } from "../components/ui/card";
import { Badge } from "../components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "../components/ui/tabs";
import { Link } from "react-router-dom";
import { signals } from "../mockData";
import { formatDistanceToNow } from "date-fns";

const iconMap = {
  'agent.reply.posted': Sparkles,
  'agent.draft.created': FileText,
  'agent.flagged': Flag,
  'agent.summarized': BarChart,
};

export function AgentActivityPage() {
  return (
    <div className="p-8">
      <div className="max-w-6xl mx-auto">
        <div className="mb-6">
          <div className="flex items-center gap-3">
            <Activity className="h-8 w-8 text-purple-600" />
            <div>
              <h1 className="text-2xl font-semibold">Agent Activity</h1>
              <p className="text-neutral-500 mt-1">Monitor agent interactions and signals</p>
            </div>
          </div>
        </div>

        <Tabs defaultValue="all" className="mt-6">
          <TabsList>
            <TabsTrigger value="all">All Events</TabsTrigger>
            <TabsTrigger value="draft">Drafts Created</TabsTrigger>
            <TabsTrigger value="flagged">Flagged</TabsTrigger>
            <TabsTrigger value="summarized">Summarized</TabsTrigger>
          </TabsList>

          <TabsContent value="all" className="mt-4">
            <div className="space-y-3">
              {signals.map((signal) => {
                const Icon = iconMap[signal.type] || Activity;
                
                return (
                  <Link key={signal.id} to={`/thread/${signal.threadId}`}>
                    <Card className="hover:border-neutral-400 transition-colors cursor-pointer">
                      <CardContent className="p-4">
                        <div className="flex gap-4">
                          <div className="p-2 bg-purple-100 rounded-full h-10 w-10 flex items-center justify-center">
                            <Icon className="h-5 w-5 text-purple-700" />
                          </div>
                          <div className="flex-1">
                            <div className="flex items-center gap-2 mb-1">
                              <span className="font-medium">{signal.type}</span>
                              <Badge variant="outline" className="text-xs bg-neutral-50">
                                Immutable
                              </Badge>
                            </div>
                            <p className="text-sm text-neutral-600 mb-2">
                              Agent {signal.agentId} in thread {signal.threadId}
                            </p>
                            <div className="flex items-center gap-3 text-xs text-neutral-500">
                              <span>{formatDistanceToNow(new Date(signal.createdAt), { addSuffix: true })}</span>
                              {signal.data.confidence && (
                                <>
                                  <span>•</span>
                                  <span>Confidence: {(signal.data.confidence * 100).toFixed(0)}%</span>
                                </>
                              )}
                            </div>
                          </div>
                        </div>
                      </CardContent>
                    </Card>
                  </Link>
                );
              })}
            </div>
          </TabsContent>

          <TabsContent value="draft">
            <div className="space-y-3">
              {signals.filter(s => s.type === 'agent.draft.created').map((signal) => (
                <Card key={signal.id}>
                  <CardContent className="p-4">
                    <div className="flex gap-4">
                      <FileText className="h-5 w-5 text-purple-600" />
                      <div>
                        <p className="font-medium">Draft created for thread {signal.threadId}</p>
                        <p className="text-sm text-neutral-500 mt-1">
                          {formatDistanceToNow(new Date(signal.createdAt), { addSuffix: true })}
                        </p>
                      </div>
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          </TabsContent>

          <TabsContent value="flagged">
            <div className="space-y-3">
              {signals.filter(s => s.type === 'agent.flagged').map((signal) => (
                <Card key={signal.id}>
                  <CardContent className="p-4">
                    <div className="flex gap-4">
                      <Flag className="h-5 w-5 text-yellow-600" />
                      <div>
                        <p className="font-medium">Content flagged in thread {signal.threadId}</p>
                        <p className="text-sm text-neutral-600">Reason: {signal.data.reason}</p>
                        <p className="text-sm text-neutral-500 mt-1">
                          {formatDistanceToNow(new Date(signal.createdAt), { addSuffix: true })}
                        </p>
                      </div>
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          </TabsContent>

          <TabsContent value="summarized">
            <div className="space-y-3">
              {signals.filter(s => s.type === 'agent.summarized').map((signal) => (
                <Card key={signal.id}>
                  <CardContent className="p-4">
                    <div className="flex gap-4">
                      <BarChart className="h-5 w-5 text-blue-600" />
                      <div>
                        <p className="font-medium">Thread summarized: {signal.threadId}</p>
                        <p className="text-sm text-neutral-500 mt-1">
                          {formatDistanceToNow(new Date(signal.createdAt), { addSuffix: true })}
                        </p>
                      </div>
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          </TabsContent>
        </Tabs>
      </div>
    </div>
  );
}
