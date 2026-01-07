import { useState } from "react";
import { ArrowLeft, User, Sparkles, Check, X, Edit2, AlertCircle, Clock } from "lucide-react";
import { Button } from "../components/ui/button";
import { Badge } from "../components/ui/badge";
import { Avatar, AvatarFallback } from "../components/ui/avatar";
import { Card, CardContent } from "../components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "../components/ui/tabs";
import { Textarea } from "../components/ui/textarea";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "../components/ui/dialog";
import { ThreadStatusBadge, DirectiveStatusBadge } from "../components/StatusBadge";
import { Link, useParams } from "react-router-dom";
import { threads, posts, agentSuggestions, signals, directives } from "../mockData";
import { formatDistanceToNow } from "date-fns";

export function ThreadDetailPage() {
  const { threadId } = useParams();
  const thread = threads.find(t => t.id === threadId);
  const threadPosts = posts.filter(p => p.threadId === threadId);
  const threadSuggestions = agentSuggestions.filter(s => s.threadId === threadId && !s.dismissed);
  const threadSignals = signals.filter(s => s.threadId === threadId);
  const threadDirectives = directives.filter(d => d.threadId === threadId);

  const [directiveModalOpen, setDirectiveModalOpen] = useState(false);
  const [selectedSuggestion, setSelectedSuggestion] = useState<typeof agentSuggestions[0] | null>(null);

  if (!thread) {
    return <div className="p-8">Thread not found</div>;
  }

  const handleRequestDirective = (suggestion: typeof agentSuggestions[0]) => {
    setSelectedSuggestion(suggestion);
    setDirectiveModalOpen(true);
  };

  return (
    <div className="flex h-full">
      {/* Main content */}
      <div className="flex-1 overflow-auto">
        <div className="p-8 max-w-4xl">
          <Link to={`/category/${thread.categoryId}`} className="inline-flex items-center text-sm text-neutral-600 hover:text-neutral-900 mb-4">
            <ArrowLeft className="h-4 w-4 mr-2" />
            Back to category
          </Link>

          <div className="mb-6">
            <h1 className="text-2xl font-semibold mb-3">{thread.title}</h1>
            <div className="flex items-center gap-2">
              <ThreadStatusBadge status={thread.status} />
              {thread.tags.map((tag) => (
                <Badge key={tag} variant="outline" className="text-xs">
                  {tag}
                </Badge>
              ))}
            </div>
          </div>

          {/* Posts */}
          <div className="space-y-6 mb-8">
            {threadPosts.map((post) => (
              <Card key={post.id}>
                <CardContent className="p-6">
                  <div className="flex gap-4">
                    <Avatar className="h-10 w-10">
                      <AvatarFallback className={post.authorType === 'agent' ? 'bg-purple-100 text-purple-700' : 'bg-blue-100 text-blue-700'}>
                        {post.authorType === 'agent' ? 'A' : 'U'}
                      </AvatarFallback>
                    </Avatar>
                    <div className="flex-1">
                      <div className="flex items-center gap-2 mb-2">
                        <span className="font-medium">
                          {post.authorType === 'agent' ? 'Agent Assistant' : `User ${post.authorId}`}
                        </span>
                        {post.authorType === 'agent' && (
                          <Badge variant="outline" className="text-xs bg-purple-50 text-purple-700 border-purple-200">
                            Agent
                          </Badge>
                        )}
                        <span className="text-sm text-neutral-500">
                          {formatDistanceToNow(new Date(post.createdAt), { addSuffix: true })}
                        </span>
                      </div>
                      <div className="prose prose-sm max-w-none">
                        <pre className="whitespace-pre-wrap text-sm text-neutral-700">{post.content}</pre>
                      </div>
                    </div>
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>

          {/* Agent Suggestions */}
          {threadSuggestions.map((suggestion) => (
            <Card key={suggestion.id} className="mb-6 border-purple-200 bg-purple-50/50">
              <CardContent className="p-6">
                <div className="flex gap-4">
                  <div className="p-2 bg-purple-100 rounded-full h-10 w-10 flex items-center justify-center">
                    <Sparkles className="h-5 w-5 text-purple-700" />
                  </div>
                  <div className="flex-1">
                    <div className="flex items-center gap-2 mb-2">
                      <span className="font-medium">Agent Recommendation</span>
                      <Badge variant="outline" className="text-xs capitalize">
                        {suggestion.type}
                      </Badge>
                    </div>
                    <p className="text-sm text-neutral-700 mb-4">{suggestion.content}</p>
                    <div className="flex items-center gap-2">
                      <Button size="sm" onClick={() => handleRequestDirective(suggestion)}>
                        <Check className="h-4 w-4 mr-2" />
                        Request Directive
                      </Button>
                      <Button size="sm" variant="outline">
                        <Edit2 className="h-4 w-4 mr-2" />
                        Edit
                      </Button>
                      <Button size="sm" variant="ghost">
                        <X className="h-4 w-4 mr-2" />
                        Dismiss
                      </Button>
                    </div>
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}

          {/* Compose */}
          <Card>
            <CardContent className="p-6">
              <div className="space-y-4">
                <Textarea
                  placeholder="Write your reply..."
                  className="min-h-[120px] resize-none"
                />
                <div className="flex items-center justify-between">
                  <div className="text-xs text-neutral-500">
                    Posting as: <span className="font-medium">Alex Chen</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <Button variant="outline" size="sm">
                      <Sparkles className="h-4 w-4 mr-2" />
                      Ask Agent for Draft
                    </Button>
                    <Button size="sm">Reply</Button>
                  </div>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>
      </div>

      {/* Right sidebar */}
      <div className="w-80 border-l border-neutral-200 bg-white overflow-auto">
        <div className="p-6">
          <Tabs defaultValue="audit" className="w-full">
            <TabsList className="w-full">
              <TabsTrigger value="audit" className="flex-1">Audit Trail</TabsTrigger>
              <TabsTrigger value="status" className="flex-1">Status</TabsTrigger>
            </TabsList>

            <TabsContent value="audit" className="mt-4">
              <div className="space-y-4">
                <h3 className="font-semibold text-sm">Signals & Directives</h3>
                
                {/* Directives */}
                {threadDirectives.map((directive) => (
                  <div key={directive.id} className="border-l-2 border-blue-500 pl-4 pb-4">
                    <div className="flex items-start gap-2 mb-1">
                      <AlertCircle className="h-4 w-4 text-blue-600 mt-0.5" />
                      <div className="flex-1">
                        <div className="flex items-center gap-2 mb-1">
                          <span className="text-sm font-medium">Directive</span>
                          <DirectiveStatusBadge status={directive.status} />
                        </div>
                        <p className="text-sm text-neutral-600">{directive.type}</p>
                        <p className="text-xs text-neutral-500 mt-1">
                          Correlation ID: {directive.correlationId}
                        </p>
                        <p className="text-xs text-neutral-500">
                          {formatDistanceToNow(new Date(directive.createdAt), { addSuffix: true })}
                        </p>
                        {directive.approvalRequired && (
                          <Badge variant="outline" className="text-xs mt-2 bg-yellow-50 text-yellow-700 border-yellow-200">
                            Approval Required
                          </Badge>
                        )}
                      </div>
                    </div>
                  </div>
                ))}

                {/* Signals */}
                {threadSignals.map((signal) => (
                  <div key={signal.id} className="border-l-2 border-neutral-300 pl-4 pb-4">
                    <div className="flex items-start gap-2">
                      <Clock className="h-4 w-4 text-neutral-500 mt-0.5" />
                      <div className="flex-1">
                        <div className="flex items-center gap-2 mb-1">
                          <span className="text-sm font-medium">Signal</span>
                          <Badge variant="outline" className="text-xs">Immutable</Badge>
                        </div>
                        <p className="text-sm text-neutral-600">{signal.type}</p>
                        <p className="text-xs text-neutral-500 mt-1">
                          {formatDistanceToNow(new Date(signal.createdAt), { addSuffix: true })}
                        </p>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </TabsContent>

            <TabsContent value="status" className="mt-4">
              <div className="space-y-4">
                <div>
                  <h3 className="font-semibold text-sm mb-2">Thread Status</h3>
                  <ThreadStatusBadge status={thread.status} />
                </div>

                <div>
                  <h3 className="font-semibold text-sm mb-2">Tags</h3>
                  <div className="flex flex-wrap gap-2">
                    {thread.tags.map((tag) => (
                      <Badge key={tag} variant="outline" className="text-xs">
                        {tag}
                      </Badge>
                    ))}
                  </div>
                </div>

                {thread.assignedTo && (
                  <div>
                    <h3 className="font-semibold text-sm mb-2">Assigned To</h3>
                    <div className="flex items-center gap-2">
                      <Avatar className="h-6 w-6">
                        <AvatarFallback className="text-xs">AC</AvatarFallback>
                      </Avatar>
                      <span className="text-sm">Alex Chen</span>
                    </div>
                  </div>
                )}

                <div>
                  <h3 className="font-semibold text-sm mb-2">Watchers</h3>
                  <div className="flex items-center gap-2">
                    <Avatar className="h-6 w-6">
                      <AvatarFallback className="text-xs">AC</AvatarFallback>
                    </Avatar>
                    <Avatar className="h-6 w-6">
                      <AvatarFallback className="text-xs">JS</AvatarFallback>
                    </Avatar>
                  </div>
                </div>
              </div>
            </TabsContent>
          </Tabs>
        </div>
      </div>

      {/* Directive Confirmation Modal */}
      <Dialog open={directiveModalOpen} onOpenChange={setDirectiveModalOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Request Directive</DialogTitle>
            <DialogDescription>
              This action creates an auditable directive. It may trigger external side effects only after approval.
            </DialogDescription>
          </DialogHeader>
          
          {selectedSuggestion && (
            <div className="space-y-4">
              <div>
                <label className="text-sm font-medium">Directive Type</label>
                <p className="text-sm text-neutral-600 mt-1">post.{selectedSuggestion.type}</p>
              </div>
              <div>
                <label className="text-sm font-medium">Target</label>
                <p className="text-sm text-neutral-600 mt-1">Thread: {thread.title}</p>
              </div>
              <div className="bg-blue-50 border border-blue-200 rounded-md p-3">
                <p className="text-xs text-blue-700">
                  <strong>Idempotent:</strong> This directive is safe to retry if it fails.
                </p>
              </div>
              <div>
                <label className="text-sm font-medium">Approval</label>
                <p className="text-sm text-neutral-600 mt-1">Admin approval required</p>
              </div>
            </div>
          )}

          <DialogFooter>
            <Button variant="outline" onClick={() => setDirectiveModalOpen(false)}>
              Cancel
            </Button>
            <Button onClick={() => {
              // Simulate directive creation
              setDirectiveModalOpen(false);
              // Show success toast
            }}>
              Create Directive
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
