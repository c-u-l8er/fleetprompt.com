import { useState } from "react";
import { ArrowLeft, Tag as TagIcon, Sparkles } from "lucide-react";
import { Button } from "../components/ui/button";
import { Input } from "../components/ui/input";
import { Textarea } from "../components/ui/textarea";
import { Card, CardContent } from "../components/ui/card";
import { Label } from "../components/ui/label";
import { Checkbox } from "../components/ui/checkbox";
import { Badge } from "../components/ui/badge";
import { Link, useParams, useNavigate } from "react-router-dom";
import { categories } from "../mockData";

export function CreateThreadPage() {
  const { categoryId } = useParams();
  const navigate = useNavigate();
  const category = categories.find(c => c.id === categoryId);
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [tags, setTags] = useState("");
  const [requestAgentTriage, setRequestAgentTriage] = useState(false);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    // Simulate thread creation
    navigate(`/category/${categoryId}`);
  };

  return (
    <div className="p-8">
      <div className="max-w-3xl mx-auto">
        <Link 
          to={`/category/${categoryId}`}
          className="inline-flex items-center text-sm text-neutral-600 hover:text-neutral-900 mb-4"
        >
          <ArrowLeft className="h-4 w-4 mr-2" />
          Back to {category?.name}
        </Link>

        <div className="mb-6">
          <h1 className="text-2xl font-semibold">Create New Thread</h1>
          <p className="text-neutral-500 mt-1">Start a new discussion in {category?.name}</p>
        </div>

        <form onSubmit={handleSubmit}>
          <Card>
            <CardContent className="p-6 space-y-6">
              <div>
                <Label htmlFor="title">Title</Label>
                <Input
                  id="title"
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder="Brief description of your question or issue"
                  className="mt-2"
                  required
                />
              </div>

              <div>
                <Label htmlFor="tags">Tags</Label>
                <div className="mt-2 flex items-center gap-2">
                  <TagIcon className="h-4 w-4 text-neutral-400" />
                  <Input
                    id="tags"
                    value={tags}
                    onChange={(e) => setTags(e.target.value)}
                    placeholder="Add tags separated by commas"
                  />
                </div>
                <p className="text-xs text-neutral-500 mt-1">
                  e.g., api, authentication, urgent
                </p>
              </div>

              <div>
                <Label htmlFor="body">Description</Label>
                <Textarea
                  id="body"
                  value={body}
                  onChange={(e) => setBody(e.target.value)}
                  placeholder="Provide detailed information about your question or issue. Include code samples, error messages, or screenshots if relevant."
                  className="mt-2 min-h-[200px] resize-none"
                  required
                />
              </div>

              <div className="flex items-start gap-3 p-4 bg-purple-50 border border-purple-200 rounded-md">
                <Checkbox
                  id="agent-triage"
                  checked={requestAgentTriage}
                  onCheckedChange={(checked) => setRequestAgentTriage(checked as boolean)}
                />
                <div className="flex-1">
                  <label htmlFor="agent-triage" className="text-sm font-medium cursor-pointer flex items-center gap-2">
                    <Sparkles className="h-4 w-4 text-purple-600" />
                    Request agent to propose first reply + triage
                  </label>
                  <p className="text-xs text-neutral-600 mt-1">
                    The agent will analyze your thread and create signals with recommendations. No side effects will occur without your approval.
                  </p>
                </div>
              </div>
            </CardContent>
          </Card>

          <div className="flex items-center justify-between mt-6">
            <Button type="button" variant="outline" onClick={() => navigate(`/category/${categoryId}`)}>
              Cancel
            </Button>
            <Button type="submit">Create Thread</Button>
          </div>
        </form>
      </div>
    </div>
  );
}
