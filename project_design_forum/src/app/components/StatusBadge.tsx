import { Badge } from "./ui/badge";
import { ThreadStatus, DirectiveStatus } from "../types";

interface ThreadStatusBadgeProps {
  status: ThreadStatus;
}

export function ThreadStatusBadge({ status }: ThreadStatusBadgeProps) {
  const variants: Record<ThreadStatus, { label: string; className: string }> = {
    open: { label: "Open", className: "bg-blue-100 text-blue-700 border-blue-200" },
    resolved: { label: "Resolved", className: "bg-green-100 text-green-700 border-green-200" },
    needs_moderator: { label: "Needs Moderator", className: "bg-yellow-100 text-yellow-700 border-yellow-200" },
    agent_draft_ready: { label: "Agent Draft Ready", className: "bg-purple-100 text-purple-700 border-purple-200" },
  };

  const config = variants[status];

  return (
    <Badge variant="outline" className={`${config.className} text-xs`}>
      {config.label}
    </Badge>
  );
}

interface DirectiveStatusBadgeProps {
  status: DirectiveStatus;
}

export function DirectiveStatusBadge({ status }: DirectiveStatusBadgeProps) {
  const variants: Record<DirectiveStatus, { label: string; className: string }> = {
    queued: { label: "Queued", className: "bg-gray-100 text-gray-700 border-gray-200" },
    running: { label: "Running", className: "bg-blue-100 text-blue-700 border-blue-200" },
    completed: { label: "Completed", className: "bg-green-100 text-green-700 border-green-200" },
    failed: { label: "Failed", className: "bg-red-100 text-red-700 border-red-200" },
  };

  const config = variants[status];

  return (
    <Badge variant="outline" className={`${config.className} text-xs`}>
      {config.label}
    </Badge>
  );
}
