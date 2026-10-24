import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { ProfileView } from "./profile-view";
const person={display_name:"Solomon K",username:"solomon",avatar_path:null,bio:"Hello",expertise:"Product building",interests:["Design","Technology"]};
describe("ProfileView",()=>{
  it("shows identity and profile details",()=>{
    render(<ProfileView person={person}/>);
    expect(screen.getByRole("heading",{name:"Solomon K"})).toBeTruthy(); expect(screen.getByText("@solomon")).toBeTruthy();
    expect(screen.getByText("Hello")).toBeTruthy(); expect(screen.getByText("Product building")).toBeTruthy(); expect(screen.getByText("Design")).toBeTruthy();
  });
  it("explains the message-request step",()=>{
    render(<ProfileView person={person} actions={<button>Send message request</button>}/>);
    expect(screen.getByRole("button",{name:"Send message request"})).toBeTruthy(); expect(screen.getByText(/first message is a request/i)).toBeTruthy();
    expect(screen.queryByText(/Paid conversations/)).toBeNull(); expect(screen.queryByText(/Booking opens/)).toBeNull();
  });
  it("shows private account details only on the owner's profile",()=>{
    const {rerender}=render(<ProfileView person={person} email="solomon@example.com"/>); expect(screen.queryByText("solomon@example.com")).toBeNull();
    rerender(<ProfileView person={person} isSelf email="solomon@example.com"/>); expect(screen.getByText("solomon@example.com")).toBeTruthy();
  });
});