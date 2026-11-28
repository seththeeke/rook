#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { RookStack } from '../lib/rook-stack';

const app = new cdk.App();

// Stack ID stays 'RepwiseStack': it owns the stateful tables and user pool, so renaming it would
// create a new stack that collides with (and cannot adopt) the existing fixed-name resources.
new RookStack(app, 'RepwiseStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION ?? 'us-east-1',
  },
});
