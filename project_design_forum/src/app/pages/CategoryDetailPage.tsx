import { Plus, Eye, EyeOff, MessageSquare, User } from "lucide-react";
import { Button } from "../components/ui/button";
import { Badge } from "../components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "../components/ui/tabs";
import { Avatar, AvatarFallback } from "../components/ui/avatar";
import { ThreadStatusBadge } from "../components/StatusBadge";
import { Link, useParams } from "react-router-dom";
import { categories, threads } from "../mockData";
import { formatDistanceToNow } from "date-fns";

export function CategoryDetailPage() {
  const { categoryId } = useParams();
  const category = categories.find(c => c.id === categoryId);
  const categoryThreads = threads.filter(t => t.categoryId === categoryId);

  if (!category) {
    return <div className="p-8">Category not found</div>;
  }

  return (
    <div className="p-8">
      <div className="max-w-6xl mx-auto">
        <div className="flex items-start justify-between mb-6">
          <div>
            <h1 className="text-2xl font-semibold">{category.name}</h1>
            <p className="text-neutral-500 mt-1">{category.description}</p>
          </div>
          <div className="flex items-center gap-2">
            <Button variant="outline">
              <Eye className="mr-2 h-4 w-4" />
              Watch
            </Button>
            <Link to={`/category/${categoryId}/new-thread`}>
              <Button>
                <Plus className="mr-2 h-4 w-4" />
                New Thread
              </Button>
            </Link>
          </div>
        </div>

        <Tabs defaultValue="all" className="mt-6">
          <TabsList>
            <TabsTrigger value="all">All</TabsTrigger>
            <TabsTrigger value="unanswered">Unanswered</TabsTrigger>
            <TabsTrigger value="needs-review">Needs Review</TabsTrigger>
            <TabsTrigger value="agent-involved">Agent Involved</TabsTrigger>
            <TabsTrigger value="my-participation">My Participation</TabsTrigger>
          </TabsList>

          <TabsContent value="all" className="mt-4">
            <div className="border border-neutral-200 rounded-lg overflow-hidden bg-white">
              {categoryThreads.length === 0 ? (
                <div className="p-12 text-center">
                  <MessageSquare className="h-12 w-12 text-neutral-400 mx-auto mb-4" />
                  <h3 className="text-lg font-semibold mb-2">No threads yet</h3>
                  <p className="text-neutral-500 mb-4">Start a new discussion in this category</p>
                  <Link to={`/category/${categoryId}/new-thread`}>
                    <Button>
                      <Plus className="mr-2 h-4 w-4" />
                      New Thread
                    </Button>
                  </Link>
                </div>
              ) : (
                <div className="divide-y divide-neutral-200">
                  {categoryThreads.map((thread) => (
                    <Link key={thread.id} to={`/thread/${thread.id}`}>
                      <div className="p-4 hover:bg-neutral-50 transition-colors">
                        <div className="flex items-start gap-4">
                          <Avatar className="h-10 w-10">
                            <AvatarFallback className={thread.authorType === 'agent' ? 'bg-purple-100 text-purple-700' : 'bg-blue-100 text-blue-700'}>
                              {thread.authorType === 'agent' ? 'A' : 'U'}
                            </AvatarFallback>
                          </Avatar>

                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-2 mb-1">
                              <h3 className="font-medium text-neutral-900 hover:text-blue-600">
                                {thread.title}
                              </h3>
                              {thread.unreadCount > 0 && (
                                <Badge className="bg-blue-500 text-white text-xs px-1.5">
                                  {thread.unreadCount} new
                                </Badge>
                              )}
                            </div>

                            <div className="flex items-center gap-3 text-sm text-neutral-500 mb-2">
                              <span>by User {thread.authorId}</span>
                              <span>•</span>
                              <span>{thread.replyCount} replies</span>
                              <span>•</span>
                              <span>
                                Last reply {formatDistanceToNow(new Date(thread.lastReply), { addSuffix: true })}
                              </span>
                            </div>

                            <div className="flex items-center gap-2">
                              <ThreadStatusBadge status={thread.status} />
                              {thread.tags.map((tag) => (
                                <Badge key={tag} variant="outline" className="text-xs">
                                  {tag}
                                </Badge>
                              ))}
                              {thread.assignedTo && (
                                <Badge variant="outline" className="text-xs">
                                  <User className="h-3 w-3 mr-1" />
                                  Assigned
                                </Badge>
                              )}
                            </div>
                          </div>
                        </div>
                      </div>
                    </Link>
                  ))}
                </div>
              )}
            </div>
          </TabsContent>

          <TabsContent value="unanswered">
            <div className="border border-neutral-200 rounded-lg p-12 text-center bg-white">
              <p className="text-neutral-500">No unanswered threads</p>
            </div>
          </TabsContent>

          <TabsContent value="needs-review">
            <div className="border border-neutral-200 rounded-lg overflow-hidden bg-white">
              <div className="divide-y divide-neutral-200">
                {categoryThreads.filter(t => t.status === 'needs_moderator').map((thread) => (
                  <Link key={thread.id} to={`/thread/${thread.id}`}>
                    <div className="p-4 hover:bg-neutral-50 transition-colors">
                      <div className="flex items-start gap-4">
                        <Avatar className="h-10 w-10">
                          <AvatarFallback>U</AvatarFallback>
                        </Avatar>
                        <div className="flex-1">
                          <h3 className="font-medium">{thread.title}</h3>
                          <div className="flex items-center gap-2 mt-2">
                            <ThreadStatusBadge status={thread.status} />
                          </div>
                        </div>
                      </div>
                    </div>
                  </Link>
                ))}
              </div>
            </div>
          </TabsContent>

          <TabsContent value="agent-involved">
            <div className="border border-neutral-200 rounded-lg p-12 text-center bg-white">
              <p className="text-neutral-500">Threads with agent participation</p>
            </div>
          </TabsContent>

          <TabsContent value="my-participation">
            <div className="border border-neutral-200 rounded-lg p-12 text-center bg-white">
              <p className="text-neutral-500">Threads you've participated in</p>
            </div>
          </TabsContent>
        </Tabs>
      </div>
    </div>
  );
}
