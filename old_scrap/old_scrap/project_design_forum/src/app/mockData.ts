import { Organization, User, Category, Thread, Post, Signal, Directive, AgentSuggestion, ModerationItem, Notification } from './types';

export const organizations: Organization[] = [
  { id: '1', name: 'Acme Corporation' },
  { id: '2', name: 'TechStart Inc' },
  { id: '3', name: 'GlobalNet Systems' },
];

export const currentUser: User = {
  id: 'user-1',
  name: 'Alex Chen',
  role: 'admin',
  organizationId: '1',
  avatar: 'AC',
};

export const categories: Category[] = [
  {
    id: 'cat-1',
    name: 'General Support',
    description: 'General questions and support requests',
    threadCount: 145,
    lastActivity: '2026-01-07T14:30:00Z',
    organizationId: '1',
  },
  {
    id: 'cat-2',
    name: 'Feature Requests',
    description: 'Propose new features and improvements',
    threadCount: 83,
    lastActivity: '2026-01-07T12:15:00Z',
    organizationId: '1',
  },
  {
    id: 'cat-3',
    name: 'Technical Issues',
    description: 'Report bugs and technical problems',
    threadCount: 62,
    lastActivity: '2026-01-07T10:45:00Z',
    organizationId: '1',
  },
  {
    id: 'cat-4',
    name: 'API & Integration',
    description: 'API documentation and integration questions',
    threadCount: 97,
    lastActivity: '2026-01-07T09:20:00Z',
    organizationId: '1',
  },
];

export const threads: Thread[] = [
  {
    id: 'thread-1',
    title: 'Unable to authenticate with API v2 endpoint',
    categoryId: 'cat-4',
    authorId: 'user-2',
    authorType: 'human',
    status: 'agent_draft_ready',
    tags: ['api', 'authentication', 'urgent'],
    replyCount: 5,
    unreadCount: 2,
    lastReply: '2026-01-07T14:30:00Z',
    createdAt: '2026-01-06T09:15:00Z',
    watching: true,
    assignedTo: 'user-1',
  },
  {
    id: 'thread-2',
    title: 'Feature request: Dark mode support',
    categoryId: 'cat-2',
    authorId: 'user-3',
    authorType: 'human',
    status: 'open',
    tags: ['feature', 'ui'],
    replyCount: 12,
    unreadCount: 0,
    lastReply: '2026-01-07T12:15:00Z',
    createdAt: '2026-01-05T10:30:00Z',
    watching: false,
  },
  {
    id: 'thread-3',
    title: 'Webhook payload missing transaction_id field',
    categoryId: 'cat-3',
    authorId: 'user-4',
    authorType: 'human',
    status: 'needs_moderator',
    tags: ['bug', 'webhooks', 'critical'],
    replyCount: 8,
    unreadCount: 3,
    lastReply: '2026-01-07T11:45:00Z',
    createdAt: '2026-01-07T08:00:00Z',
    watching: true,
  },
  {
    id: 'thread-4',
    title: 'How to configure rate limiting?',
    categoryId: 'cat-1',
    authorId: 'user-5',
    authorType: 'human',
    status: 'resolved',
    tags: ['configuration', 'rate-limiting'],
    replyCount: 3,
    unreadCount: 0,
    lastReply: '2026-01-06T16:20:00Z',
    createdAt: '2026-01-06T14:10:00Z',
    watching: false,
  },
];

export const posts: Post[] = [
  {
    id: 'post-1',
    threadId: 'thread-1',
    authorId: 'user-2',
    authorType: 'human',
    content: 'I\'m attempting to authenticate with the v2 API endpoint using OAuth 2.0, but consistently receiving a 401 Unauthorized response. I\'ve verified my client credentials are correct and the token endpoint is returning a valid access token.\n\n```bash\ncurl -X POST https://api.fleetprompt.com/v2/auth/token \\\n  -H "Authorization: Bearer eyJhbGc..." \\\n  -H "Content-Type: application/json"\n```\n\nError response:\n```json\n{\n  "error": "unauthorized",\n  "message": "Invalid or expired token"\n}\n```\n\nAny guidance would be appreciated.',
    createdAt: '2026-01-06T09:15:00Z',
  },
  {
    id: 'post-2',
    threadId: 'thread-1',
    authorId: 'agent-1',
    authorType: 'agent',
    content: 'I\'ve analyzed your request and identified a potential issue with token scope. The v2 endpoint requires the `api:write` scope in addition to `api:read`. Could you verify your OAuth configuration includes both scopes?',
    createdAt: '2026-01-06T09:45:00Z',
  },
];

export const agentSuggestions: AgentSuggestion[] = [
  {
    id: 'sug-1',
    threadId: 'thread-1',
    type: 'summary',
    content: 'User experiencing OAuth authentication failures with v2 API. Preliminary analysis suggests missing token scope. Recommended action: verify OAuth scope configuration.',
    createdAt: '2026-01-06T09:30:00Z',
  },
  {
    id: 'sug-2',
    threadId: 'thread-1',
    type: 'reply',
    content: 'Based on the error message and your configuration, it appears your OAuth token is missing the required `api:write` scope. To resolve this:\n\n1. Update your OAuth client configuration to request both `api:read` and `api:write` scopes\n2. Re-authenticate to obtain a new token with the correct scopes\n3. Verify the token includes both scopes using our token introspection endpoint\n\nRelevant documentation: https://docs.fleetprompt.com/api/v2/authentication#scopes',
    createdAt: '2026-01-06T10:00:00Z',
  },
  {
    id: 'sug-3',
    threadId: 'thread-3',
    type: 'moderation',
    content: 'This thread contains technical details that may require engineering review. Recommend escalation to engineering team.',
    createdAt: '2026-01-07T11:50:00Z',
  },
];

export const signals: Signal[] = [
  {
    id: 'sig-1',
    type: 'agent.draft.created',
    threadId: 'thread-1',
    agentId: 'agent-1',
    data: { suggestionId: 'sug-2', confidence: 0.92 },
    createdAt: '2026-01-06T10:00:00Z',
    immutable: true,
  },
  {
    id: 'sig-2',
    type: 'agent.summarized',
    threadId: 'thread-1',
    agentId: 'agent-1',
    data: { suggestionId: 'sug-1' },
    createdAt: '2026-01-06T09:30:00Z',
    immutable: true,
  },
  {
    id: 'sig-3',
    type: 'agent.flagged',
    threadId: 'thread-3',
    agentId: 'agent-1',
    data: { reason: 'requires_engineering_review', confidence: 0.87 },
    createdAt: '2026-01-07T11:50:00Z',
    immutable: true,
  },
];

export const directives: Directive[] = [
  {
    id: 'dir-1',
    type: 'post.publish',
    threadId: 'thread-1',
    initiatedBy: 'user-1',
    status: 'completed',
    correlationId: 'cor-1a2b3c4d',
    target: 'post-2',
    approvalRequired: false,
    createdAt: '2026-01-06T10:05:00Z',
    completedAt: '2026-01-06T10:05:30Z',
  },
  {
    id: 'dir-2',
    type: 'thread.escalate',
    threadId: 'thread-3',
    initiatedBy: 'agent-1',
    status: 'queued',
    correlationId: 'cor-5e6f7g8h',
    target: 'team:engineering',
    approvalRequired: true,
    createdAt: '2026-01-07T11:52:00Z',
  },
];

export const moderationQueue: ModerationItem[] = [
  {
    id: 'mod-1',
    contentId: 'thread-3',
    contentType: 'thread',
    reason: 'Requires engineering review',
    reportedBy: 'agent-1',
    reportedAt: '2026-01-07T11:50:00Z',
    contentPreview: 'Webhook payload missing transaction_id field - appears to be a critical bug affecting multiple customers...',
    signals: [signals[2]],
    directives: [directives[1]],
  },
];

export const notifications: Notification[] = [
  {
    id: 'notif-1',
    type: 'mention',
    message: 'Sarah mentioned you in "API Authentication Issues"',
    read: false,
    createdAt: '2026-01-07T14:30:00Z',
    link: '/thread/thread-1',
  },
  {
    id: 'notif-2',
    type: 'directive',
    message: 'Directive "Post to external system" completed successfully',
    read: false,
    createdAt: '2026-01-07T12:15:00Z',
    link: '/thread/thread-1',
  },
  {
    id: 'notif-3',
    type: 'assignment',
    message: 'You were assigned to "Unable to authenticate with API v2 endpoint"',
    read: true,
    createdAt: '2026-01-07T10:00:00Z',
    link: '/thread/thread-1',
  },
];
