// FleetPrompt Forum Types

export type UserRole = 'owner' | 'admin' | 'member';
export type ParticipantType = 'human' | 'agent';
export type ThreadStatus = 'open' | 'resolved' | 'needs_moderator' | 'agent_draft_ready';
export type DirectiveStatus = 'queued' | 'running' | 'completed' | 'failed';
export type SignalType = 'agent.reply.posted' | 'agent.draft.created' | 'agent.flagged' | 'agent.summarized';

export interface Organization {
  id: string;
  name: string;
}

export interface User {
  id: string;
  name: string;
  avatar?: string;
  role: UserRole;
  organizationId: string;
}

export interface Agent {
  id: string;
  name: string;
  type: ParticipantType;
}

export interface Category {
  id: string;
  name: string;
  description: string;
  threadCount: number;
  lastActivity: string;
  organizationId: string;
}

export interface Thread {
  id: string;
  title: string;
  categoryId: string;
  authorId: string;
  authorType: ParticipantType;
  status: ThreadStatus;
  tags: string[];
  replyCount: number;
  unreadCount: number;
  lastReply: string;
  createdAt: string;
  watching: boolean;
  assignedTo?: string;
}

export interface Post {
  id: string;
  threadId: string;
  authorId: string;
  authorType: ParticipantType;
  content: string;
  createdAt: string;
  attachments?: string[];
}

export interface AgentSuggestion {
  id: string;
  threadId: string;
  type: 'summary' | 'reply' | 'moderation' | 'routing';
  content: string;
  createdAt: string;
  dismissed?: boolean;
}

export interface Signal {
  id: string;
  type: SignalType;
  threadId: string;
  agentId: string;
  data: any;
  createdAt: string;
  immutable: true;
}

export interface Directive {
  id: string;
  type: string;
  threadId: string;
  initiatedBy: string;
  status: DirectiveStatus;
  correlationId: string;
  target: string;
  approvalRequired: boolean;
  createdAt: string;
  completedAt?: string;
}

export interface ModerationItem {
  id: string;
  contentId: string;
  contentType: 'post' | 'thread';
  reason: string;
  reportedBy: string;
  reportedAt: string;
  contentPreview: string;
  signals: Signal[];
  directives: Directive[];
}

export interface Notification {
  id: string;
  type: string;
  message: string;
  read: boolean;
  createdAt: string;
  link?: string;
}
